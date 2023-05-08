#!/bin/bash
GREEN='\033[0;32m'
CYAN='\033[0;36m'
RED='\033[0;31m'
# no color
NC='\033[0m'

set -e # exit on error

function fail() {
  echo -e "$RED===== $1 =====$NC"
  exit 1
}

function success() {
  echo -e "$GREEN===== $1 =====$NC"
}

function info() {
  echo -e "$CYAN===== $1 =====$NC"
}

function cleanup() {
  # cleanup for previous runs
  cont_dev=$(/sbin/losetup -a | grep container.img | grep -Eo '/dev/loop[0-9]' || true) # find existing loopbacks with container fs image
  # check if cont_dev is not empty
  if [[ ! -z "$cont_dev" ]] ; then
    info "cleaning up..."
    rm -f rootfs.tar.gz
    umount ./container_root/proc || true
    umount ./container_root/sys || true
    umount ./container_root || true
    losetup -d $cont_dev || true # remove existing loopback if any
    rm -rf ./container_root || true
    info "clean up done"
  fi
}

function create_img() {
  info "creating container image..."
  dd if=/dev/zero of=./container.img bs=1M count=1024
  mkfs.ext4 ./container.img
  info "container image created"
}

function mount_img() {
  info "mounting container image..."
  # mount fs image to loopback
  losetup -f ./container.img
  # update container dev var
  cont_dev="$(/sbin/losetup -a | grep container.img | grep -Eo '/dev/loop[0-9]')"
  mkdir -p ./container_root
  mount "$cont_dev" ./container_root
  info "container image mounted"
}

function setup_rootfs() {
  info "setting up rootfs..."
#  if [[ ! -e rootfs.tar.gz ]] ; then
#   wget http://cdimage.ubuntu.com/ubuntu-base/releases/20.04/release/ubuntu-base-20.04.1-base-amd64.tar.gz -O rootfs.tar.gz
#  fi
#  tar -xzf ./rootfs.tar.gz -C ./container_root
  tar -xzf ../deps/rootfs.tar.gz -C ./container_root
  info "rootfs setup done"
}

function add_network_namespace() {
  NS_NAME="container_network_ns"
  CONTAINER_VETH="veth_container"
  HOST_VETH="veth_host"
  HOST_IP="192.168.10.1"
  CONTAINER_IP="192.168.10.2"
  # Delete the veth pair interfaces
  ip link delete "$CONTAINER_VETH" || true
  ip link delete "$HOST_VETH" || true
  # Delete the network namespace
  ip netns delete "$NS_NAME" || true
  info "adding network namespace..."
  # Create a network namespace
  ip netns add $NS_NAME
  # Create a virtual network interface pair
  ip link add $HOST_VETH type veth peer name $CONTAINER_VETH
  # Move the container-side interface to the container namespace
  ip link set $CONTAINER_VETH netns $NS_NAME
  # Configure IP addresses for the interfaces
  ip addr add $HOST_IP/24 dev $HOST_VETH
  ip netns exec $NS_NAME ip addr add $CONTAINER_IP/24 dev $CONTAINER_VETH
  # Enable network interfaces
  ip link set $HOST_VETH up
  ip netns exec $NS_NAME ip link set $CONTAINER_VETH up
  # Enable IP forwarding
  echo 1 > /proc/sys/net/ipv4/ip_forward
  # Set up network routing
  ip netns exec $NS_NAME ip route add default via $HOST_IP
  info "add network namespace done"
}

function main() {
  # check if running as root
  if [[ $EUID -ne 0 ]]; then
     fail "This script must be run as root"
  fi
  projdir="$(pwd)"
  mkdir -p ./container
  pushd ./container
  cleanup
  create_img
  mount_img
  setup_rootfs
  add_network_namespace
  echo -e "$GREEN===== init container done =====$NC"
}

main
