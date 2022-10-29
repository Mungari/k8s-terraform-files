#!/bin/bash

# VARS #
TERRAFORM_FILES_PATH="/home/fmungari/Documents/k8s/k8s-terraform-files"
CFG_PATH="/home/fmungari/Documents/k8s/k8s-terraform-files/configs"
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
  ./destroy_cluster.sh
}

create_cluster() {
  sudo terraform -chdir=$TERRAFORM_FILES_PATH init
  sudo terraform  -chdir=$TERRAFORM_FILES_PATH plan
  sudo terraform -chdir=$TERRAFORM_FILES_PATH apply -auto-approve
  echo "Wait 30 seconds for the IPs to become available..."
  sleep 30
  echo "your cluster IPs are:"
  for instance in $(sudo virsh list --all | grep k8s | awk {'print $2'} | sort); do
    echo "$instance"
    ssh_string = ssh -i $CFG_PATH/root root@$host
    if [[ $instance == *"k8s"* ]]; then
    host=$(sudo virsh domifaddr $instance | grep -ohe "192.*" | cut -d"/" -f1)
    $ssh_string cat <<EOF | tee /etc/yum.repos.d/kubernetes.repo
      [kubernetes]
      name=Kubernetes
      baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-\$basearch
      enabled=1
      gpgcheck=1
      gpgkey=https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
      exclude=kubelet kubeadm kubectl 
EOF
    $ssh_string setenforce 0
    $ssh_string sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
    $ssh_string yum install docker -y
    $ssh_string yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
    $ssh_string systemctl enable --now kubelet
    case $instance in
    *"master"*)
      $ssh_string kubeadm-init --pod-network-cidr 10.10.14.0/24
      #token_hash = $ssh_string openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | \
      #openssl dgst -sha256 -hex | sed 's/^.* //'
      #k8s_master_host = $host 
      token = $ssh_string -c "kubeadm token list | awk 'NR == 2 {print $1}'"
      join_command = $ssh_string kubeadm token create $token** --print-join-command
      echo "$join_command"
      ;;
    *"worker"*)
      echo "ansible_host=$(sudo virsh domifaddr $instance | grep -ohe "192.*" | cut -d"/" -f1)" >> $ANSIBLE_HOST_FILE_PATH
      ;;
      esac
  fi
  done
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
        echo "" > /home/fmungari/Documents/k8s/ansible_kubernetes/inventory/hosts
        create_cluster
      else
        echo "No refuse files found, nothing to do, creating cluster..."
        create_cluster
      fi
  fi
