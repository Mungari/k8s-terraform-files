#!/bin/bash
TERRAFORM_FILES_PATH="/home/fmungari/Documents/k8s/k8s-terraform-files"


destroy_cluster() {
  sudo terraform -chdir=$TERRAFORM_FILES_PATH destroy -auto-approve
  # for instance in $(sudo virsh list --all | grep k8s | awk {'print $2'}); do
  #   sudo virsh destroy $instance
  #   sudo virsh undefine $instance
  # done
  # sudo rm -f /kvm/pools/homelab/k8s*
  # sudo rm -f /var/lib/libvirt/dnsmasq/virbr0.*
  # sudo rm -f $TERRAFORM_FILES_PATH/terraform.tfstate $TERRAFORM_FILES_PATH/terraform.tfstate.backup
}

read -p "Are you sure? [y/N - default no]" confirm
confirm=${confirm:-n}
case $confirm in
  y)
  echo "Destroying cluster..."
  destroy_cluster
  exit 0
  ;;
  *)
  echo "Exiting..."
  exit -1
  ;;
esac
