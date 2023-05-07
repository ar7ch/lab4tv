#!/bin/bash
GREEN='\033[0;32m'
CYAN='\033[0;36m'
RED='\033[0;31m'
# no color
NC='\033[0m'

set -e # exit on error
# check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "$RED===== This script must be run as root =====$NC"
   exit 1
fi
mkdir -p ./container
pushd ./container
# cleanup for previous runs
cont_dev=$(/sbin/losetup -a | grep container.img | grep -Eo '/dev/loop[0-9]') # find existing loopbacks with container fs image
# check if cont_dev is not empty
if [[ ! -z "$cont_dev" ]] ; then
  echo -e "$CYAN===== cleaning up =====$NC"
  rm -f rootfs.tar.gz
  umount ./container_root || true
  losetup -d $cont_dev || true # remove existing loopback if any
fi

#create container fs image
dd if=/dev/zero of=./container.img bs=1024K count=100
mkfs.ext4 ./container.img
# mount fs image to loopback
losetup -f ./container.img
# update container dev var
cont_dev="$(/sbin/losetup -a | grep container.img | grep -Eo '/dev/loop[0-9]')"
mkdir -p ./container_root
mount "$cont_dev" ./container_root
if [[ ! -e rootfs.tar.gz ]] ; then
	wget http://cdimage.ubuntu.com/ubuntu-base/releases/20.04/release/ubuntu-base-20.04.1-base-amd64.tar.gz -O rootfs.tar.gz
fi
tar -xzf ./rootfs.tar.gz -C ./container_root
echo -e "$GREEN===== init container done =====$NC"
