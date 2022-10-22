terraform {
  required_providers {
    cloudinit = {
      source = "hashicorp/cloudinit"
      version = "2.2.0"
    }
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

data "template_file" "user_data" {
  template = "${file("${path.module}/configs/users_and_groups.cfg")}"
}

locals {
  k8s-nodes = {
  "k8s-master" = {disk = "k8s-master.qcow2"},
  "k8s-worker-1" = {disk = "k8s-worker-1.qcow2"},
  "k8s-worker-2" = {disk = "k8s-worker-2.qcow2"}
  }
}

resource "libvirt_cloudinit_disk" "commoninit" {
  for_each = local.k8s-nodes

  name = format("%s%s",each.key,"commoninit.iso")
  pool = "default"
  user_data  = "${data.template_file.user_data.rendered}"
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
    cloudinit = "${libvirt_cloudinit_disk.commoninit[each.key].id}"
    console {
        type = "pty"
        target_type = "serial"
        target_port = "0"
    }
}
