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
  exit 0
}

destroy_cluster() {
  ./destroy_cluster.sh
}

sp="/-\|"
sc=0
spin() {
   printf "\b${sp:sc++:1}"
   ((sc==${#sp})) && sc=0
}

create_cluster() {
  sudo terraform -chdir=$TERRAFORM_FILES_PATH init
  sudo terraform  -chdir=$TERRAFORM_FILES_PATH plan
  sudo terraform -chdir=$TERRAFORM_FILES_PATH apply -auto-approve
  conn_result=1
  ip_aval=1
  echo "Wait 30 seconds for the IPs to become available..."
  while [[ $ip_aval -ne 0 ]]; do
    if [[ $(sudo virsh net-dhcp-leases default | wc -l) -le 3 ]]; then
      spin
    else
      ip_aval=0
    fi
  done 
  echo "your cluster IPs are:"
  for instance in $(sudo virsh list --all | grep k8s | awk {'print $2'} | sort); do
    echo "$instance"
    #ssh_string = ssh -i $CFG_PATH/root root@$host
    if [[ $instance == *"k8s"* ]]; then
    host=$(sudo virsh domifaddr $instance | grep -ohe "192.*" | cut -d"/" -f1)
    echo $host
    echo "conn test"
    while [[ $conn_result -ne 0 ]]; do
      spin
      ssh -o StrictHostKeyChecking=no -i $CFG_PATH/root root@$host whoami > /dev/null 2>&1
      conn_result=$?
    done
    ssh -o StrictHostKeyChecking=no -i $CFG_PATH/root root@$host yum-config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
    ssh -o StrictHostKeyChecking=no -i $CFG_PATH/root root@$host "cat <<EOF | tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kubelet kubeadm kubectl 
EOF" 1>/dev/null
    ssh -o StrictHostKeyChecking=no -i $CFG_PATH/root root@$host "echo 'net.ipv4.ip_forward = 1' > /etc/sysctl.conf"
    ssh -o StrictHostKeyChecking=no -i $CFG_PATH/root root@$host "echo 'net.bridge.bridge-nf-call-iptables = 1' >> /etc/sysctl.conf"
    ssh -o StrictHostKeyChecking=no -i $CFG_PATH/root root@$host "modprobe bridge; modprobe br_netfilter; sysctl -p"
    ssh -o StrictHostKeyChecking=no -i $CFG_PATH/root root@$host "setenforce 0" 1>/dev/null
    ssh -o StrictHostKeyChecking=no -i $CFG_PATH/root root@$host "sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config" 1>/dev/null
    ssh -o StrictHostKeyChecking=no -i $CFG_PATH/root root@$host "yum install containerd -y" 1>/dev/null
    ssh -o StrictHostKeyChecking=no -i $CFG_PATH/root root@$host "yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes" 1>/dev/null
    ssh -o StrictHostKeyChecking=no -i $CFG_PATH/root root@$host "systemctl enable --now kubelet; systemctl enable --now containerd" 1>/dev/null
    ssh -o StrictHostKeyChecking=no -i $CFG_PATH/root root@$host "rm -rf /etc/containerd/config.toml; systemctl restart containerd" 1>/dev/null
    case $instance in
    *"master"*)
      ssh -o StrictHostKeyChecking=no -i $CFG_PATH/root root@$host "kubeadm init --pod-network-cidr 10.10.14.0/24" 1>/dev/null
      ssh -o StrictHostKeyChecking=no -i $CFG_PATH/root root@$host "mkdir /root/.kube; cp /etc/kubernetes/admin.conf /root/.kube/config" 1>/dev/null
      k8s_master_host=$host 
      join_command=$(ssh -o StrictHostKeyChecking=no -i $CFG_PATH/root root@$host "kubeadm token create --print-join-command")
      echo "$join_command"
      ;;
    *"worker"*)
      echo "ansible_host=$(sudo virsh domifaddr $instance | grep -ohe "192.*" | cut -d"/" -f1)"
      ssh -o StrictHostKeyChecking=no -i $CFG_PATH/root root@$host "$join_command"
      ;;
      esac
  fi
  done
}

check_cluter_create () {
  echo "Checking cluster is up and running"
  for i in {1..10}; do
    echo "Try $i/10"
    ssh -o StrictHostKeyChecking=no -i $CFG_PATH/root root@$k8s_master_host "kubectl get nodes" 1>/dev/null
    cluster_health=$?
    if [[ $cluster_health -ne 0 ]]; then
      if [[ $i -eq 10 ]]; then
        echo "Cluster is not healthy, reached maximum retry attempts, FATAL"
        exit -1
      fi
    echo "Cluster is not healthy, retrying..."
    sleep 0.5
    else
      echo "Cluster is up and running"
      exit 0
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
      check_cluter_create
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