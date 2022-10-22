#!/bin/bash

# VARS #
TERRAFORM_FILES_PATH="/home/fmungari/Documents/k8s/k8s-terraform-files"

check_status() {
  for instance in $(sudo virsh list --all | grep k8s | awk {'print $2'}); do
    echo "Checking $instance state... stand by!"
  	case $(sudo virsh domstate $instance) in
    "shut off")
      echo "Starting VM $instance..."
      sudo virsh start $instance
      ;;
    "running")
      echo "$instance VM is running, nothing to do..."
      ;;
  	esac
  done
}

destroy_cluster() {
  for instance in $(sudo virsh list --all | grep k8s | awk {'print $2'}); do
    sudo virsh destroy $instance
    sudo virsh undefine $instance
  done
  sudo rm -f /kvm/pools/homelab/k8s*
  sudo rm -f /var/lib/libvirt/dnsmasq/virbr0.*
  sudo rm -f $TERRAFORM_FILES_PATH/terraform.tfstate $TERRAFORM_FILES_PATH/terraform.tfstate.backup
}

create_cluster() {
  sudo rm -f $TERRAFORM_FILES_PATH/terraform.tfstate $TERRAFORM_FILES_PATH/terraform.tfstate.backup
  sudo terraform -chdir=$TERRAFORM_FILES_PATH init
  sudo terraform  -chdir=$TERRAFORM_FILES_PATH plan
  sudo terraform -chdir=$TERRAFORM_FILES_PATH apply -auto-approve
}
echo "Checking if cluster is up and running..."
if [[ $(sudo virsh list --all | grep k8s) ]]; then
  read -p "Found cluster VMs, do you want to clean it up and start a new one? [y/n - default no]"  destroy
  destroy=${destroy:-n} 
  case $destroy in
    "y")
      destroy_cluster
      create_cluster
      ;;
    "n")
      check_status
      ;;
  esac
  else
    echo "Cluster not found, checking for refuse files..."
      if [[ $(sudo ls /kvm/pools/homelab | grep k8s) ]]; then
        echo "Found refuse files, cleaning up..."
        sudo rm -f /kvm/pools/homelab/k8s*
        sudo rm -f /var/lib/libvirt/dnsmasq/virbr0.*
        create_cluster
      else
        echo "No refuse files found, nothing to do, creating cluster..."
        create_cluster
      fi
  fi
  echo "Wait 30 seconds for the IPs to become available..."
  sleep 30
  echo "your cluster IPs are:"
  for instance in $(sudo virsh list --all | grep k8s | awk {'print $2'}); do
    echo "$instance"
    sudo virsh domifaddr $instance
  done
