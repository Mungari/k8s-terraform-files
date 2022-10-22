terraform {
  required_providers {
    libvirt = {
      source = "dmacvicar/libvirt"
      version = "0.7.0"
    }
  }
}

provider "libvirt" {
  # Configuration options
  # Configure kvm host
  uri = "qemu:///system" #Quemu host
}

# Create disk that contains image
resource "libvirt_volume" "centos"{
    for_each = toset(["k8s-master.qcow2", "k8s-worker-1.qcow2","k8s-worker-2.qcow2"])
    name = each.key
    pool = "default"
    source = "./images/centos-7.qcow2" #yoink from cloud
    format = "qcow2"
}

locals {
  k8s-nodes = {
  "k8s-master" = {disk = "k8s-master.qcow2"},
  "k8s-worker-1" = {disk = "k8s-worker-1.qcow2"},
  "k8s-worker-2" = {disk = "k8s-worker-2.qcow2"}
  }
}


resource "libvirt_domain" "k8s-nodes"{
    for_each = local.k8s-nodes

    name = each.key
    memory = "2048"
    vcpu = "1" # Consider upping to 2
    network_interface {
        network_name = "default" # List networks with virsh net-list
    }
    disk {
        volume_id = "${libvirt_volume.centos[each.value.disk].id}"
    }
    console {
        type = "pty"
        target_type = "serial"
        target_port = "0"
    }
}

# output "ip" {
#     #for_each = local.k8s-nodes
#     value = toset([
#         for k8s in libvirt_domain.k8s-nodes : "${k8s.network_interface.0.addresses.0}"
#     ])
# }