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
    umount ./container_root
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
  info "downloading and setting up rootfs..."
  if [[ ! -e rootfs.tar.gz ]] ; then
    wget http://cdimage.ubuntu.com/ubuntu-base/releases/20.04/release/ubuntu-base-20.04.1-base-amd64.tar.gz -O rootfs.tar.gz
  fi
  tar -xzf ./rootfs.tar.gz -C ./container_root
  info "rootfs setup done"
}

function add_deps() {
  info "adding dependencies..."
  # add sysbench to container
  cp "$projdir/deps/sysbench" ./container_root/bin/sysbench -v
  cp "$projdir/deps/libaio.so" ./container_root/lib/x86_64-linux-gnu/libaio.so.1 -v
  info "add deps done"
}

function add_network_namespace() {
  NS_NAME="container_network_ns"
  VETH_CONTAINER_NAME="veth_container"
  VETH_HOST_NAME="veth_host"
  HOST_IP="192.168.10.1"
  CONTAINER_IP="192.168.10.2"
  # Delete the veth pair interfaces
  ip link delete "$VETH_CONTAINER_NAME" || true
  ip link delete "$VETH_HOST_NAME" || true
  # Delete the network namespace
  ip netns delete "$NS_NAME"
  info "adding network namespace..."
  # Create a network namespace
  ip netns add container_ns
  # Create a virtual network interface pair
  ip link add $VETH_HOST_NAME type veth peer name $VETH_CONTAINER_NAME
  # Move the container-side interface to the container namespace
  ip link set $VETH_CONTAINER_NAME netns $NS_NAME
  # Configure IP addresses for the interfaces
  ip addr add $HOST_IP/24 dev veth_host
  ip netns exec $NS_NAME ip addr add $CONTAINER_IP/24 dev VETH_CONTAINER_NAME
  # Enable network interfaces
  ip link set veth_host up
  ip netns exec $NS_NAME ip link set $VETH_CONTAINER_NAME up
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