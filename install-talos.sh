#!/bin/bash

# Exit on any error
set -e

# Define variables
TALOS_VERSION="v1.9.5"
TALOS_IMAGE_URL="https://factory.talos.dev/image/376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba/v1.9.5/metal-amd64.raw.xz"
CONFIG_URL="http://<your-workstation-ip>:8000/controlplane.yaml"  # Replace with your hosted config URL

# Install required tools
apt-get update
apt-get install -y wget xz-utils

# Wipe disks
wipefs -a /dev/nvme0n1
wipefs -a /dev/nvme1n1
dd if=/dev/zero of=/dev/nvme0n1 bs=512 count=1
dd if=/dev/zero of=/dev/nvme1n1 bs=512 count=1
sync

# Partition /dev/nvme0n1
(
echo g              # Create a new GPT partition table
echo n              # New partition
echo 1              # Partition number 1
echo 2048           # First sector
echo +100M          # Size 100M
echo t              # Change type
echo ef             # EFI System
echo n              # New partition
echo 2              # Partition number 2
echo 206848         # First sector
echo                # Default (rest of disk)
echo t              # Change type
echo 2              # Partition 2
echo fd             # Linux RAID autodetect
echo w              # Write changes
) | fdisk /dev/nvme0n1

# Partition /dev/nvme1n1 (mirror of nvme0n1)
(
echo g
echo n
echo 1
echo 2048
echo +100M
echo t
echo ef
echo n
echo 2
echo 206848
echo
echo t
echo 2
echo fd
echo w
) | fdisk /dev/nvme1n1

# Create RAID 1 array
mdadm --create /dev/md0 --level=1 --raid-devices=2 /dev/nvme0n1p2 /dev/nvme1n1p2
mdadm --wait /dev/md0

# Download and install Talos
wget $TALOS_IMAGE_URL -O /tmp/metal-amd64.raw.xz
xz -d /tmp/metal-amd64.raw.xz
dd if=/tmp/metal-amd64.raw of=/dev/md0 bs=4M status=progress
sync

# Format the EFI partition on /dev/nvme0n1p1
mkfs.vfat -F 32 /dev/nvme0n1p1

# Mount and copy bootloader
mkdir -p /mnt/talos-efi /mnt/boot
mount /dev/md0p1 /mnt/talos-efi
mount /dev/nvme0n1p1 /mnt/boot
cp -r /mnt/talos-efi/* /mnt/boot/
umount /mnt/talos-efi /mnt/boot

# Apply controlplane.yaml to the STATE partition
mkdir -p /mnt/talos-state
mount /dev/md0p3 /mnt/talos-state
mkdir -p /mnt/talos-state/system/state
wget $CONFIG_URL -O /mnt/talos-state/system/state/config.yaml
sync
umount /mnt/talos-state

# Reboot
reboot
