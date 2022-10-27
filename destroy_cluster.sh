#!/bin/bash
TERRAFORM_FILES_PATH="/home/fmungari/Documents/k8s/k8s-terraform-files"


destroy_cluster() {
  sudo terraform -chdir=$TERRAFORM_FILES_PATH destroy -auto-approve
  echo "" > /home/fmungari/Documents/k8s/ansible_kubernetes/inventory/hosts
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
