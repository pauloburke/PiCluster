# PiCluster

Code and Documentation for setting up a RaspberryPi Cluster


## Installing Raspberry Pi OS

1. Download the Raspberry Pi Imager from [here](https://www.raspberrypi.org/software/) and install it.
2. Download the Raspberry Pi OS Lite (64-bit) option for Operating System [here](https://www.raspberrypi.com/software/operating-systems/).
3. Follow the instructions to select the volume (Micro SD card) and image.
4. Edit the configurations setting the hostname (e.g. k8-1, k8-2...), user and password, and enabling password SSH.
5. Write the image to the SD card.

## Setup Ansible

1. Install Ansible
```bash
pip3 install ansible
```

## General Raspberry Pi Setup

The following ansible playbook will setup the Raspberry Pi OS with the following configurations:
1. Update Raspberry Pi OS
2. Install tools
3. Add configuration to `/boot/firmware/cmdline.txt`
4. Add PoE HAT fan configuration to `/boot/config.txt`
5. Reboot the server

```bash
ansible-playbook -i hosts playbooks/basic_setup/raspberry_pi_initial_setup.yml
```

## Setting up NFS Server

The following ansible playbook will setup the NFS server with the following configurations:

1. Create a new partition on the SSD
2. Create a new directory and mount the SSD
3. Add the volume to `/etc/fstab`
4. Install NFS Server
5. Create a mount point for the NFS share (e.g. `/nfs`)
6. Add the NFS share to `/etc/exports`
7. Restart the NFS server

```bash
ansible-playbook -i hosts playbooks/basic_setup/nfs_server_setup.yml
```
> This playbook assumes that the SSD is available at `/dev/sda`.

## Setting up MicroK8s

The following ansible playbook will setup MicroK8s by executing the following steps:

1. Install snapd
2. Install snap core
3. Install MicroK8s
4. Add user to MicroK8s group
5. Wait MicroK8s to be ready
6. Enable MicroK8s to start on boot

```bash
ansible-playbook -i hosts playbooks/microk8s/basic_setup.yml
```

## Adding a new node to the cluster

1. Run the following Ansible playbook to add the new node to the `/etc/hosts` file of all master nodes.

```bash
ansible-playbook -i hosts playbooks/microk8s/add_node_to_hosts.yml -e "new_node_ip=192.168.0.11 new_node_hostname=k8-1"
```
> Replace `new_node_ip` and `new_node_hostname` with the IP address and hostname of the new node.

2. Run the following command to get the join command:
```bash
microk8s add-node
```

3. SSH into the new node and run the join command obtained in step 2.

## Setting up the Master Node

SSH into the master node and run the following commands:

1. Enable MicroK8s addons
```bash
microk8s enable dns 
microk8s enable helm
microk8s enable cert-manager
microk8s enable dashboard
microk8s enable ingress
```

2. Enable MetalLB
```bash
microk8s enable metallb:192.168.0.50-192.168.0.99
```
> Make sure that this IP range is not used by your router.

3. Wait for pods to be ready
```bash
watch -n 1 microk8s kubectl get all --all-namespaces
```
> If ingress fails to start, reboot the server.

4. Create cluster issuer for cert-manager
```bash
export CLUSTER_ISSUER_EMAIL=your-email@example.com
envsubst < kubernetes/basic_setup/cluster-issuer.yml | microk8s kubectl apply -f -
```
> Make sure to change the email address in the file.

7. Clone this repo
```bash
git clone https://github.com/pauloburke/PiCluster.git
```

8. Add Ingress rule for dashboard
```bash
microk8s kubectl apply -f PiCluster/kubernetes/basic_setup/ingress-kubernetes-dashboard.yaml
```
> The dashboard will be available at `https://k8-1/dashboard/`. Make sure that you added the hostname to your `/etc/hosts` file.

9. Get the token to access the dashboard
```bash
microk8s kubectl describe secret -n kube-system microk8s-dashboard-token
```

10. Create cluster issuer for cert-manager
```bash
microk8s kubectl apply -f PiCluster/cluster-issuer.yml
```
> Make sure to change the email address in the file.
<!-- Change to email env variable -->

11. Create a NFS storage class
```bash
microk8s helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
microk8s helm install nfs-subdir-external-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
    --set nfs.server=192.168.50.1 \
    --set nfs.path=/nfs
```

## Adding Worker Nodes

You can use `parallel-ssh` to run commands on multiple nodes at the same time.
So as a first step, add the worker node to the `~/.pssh_hosts` file:
```bash
k8-worker-1
k8-worker-2
k8-worker-3
...
``` 

Example:
```bash
parallel-ssh -h ~/.pssh_hosts -i "sudo apt update && sudo apt dist-upgrade -y"
```

### Installing Raspberry Pi OS

Assuming that the master node is already setup, we will use the same image to setup the worker nodes.
However, we will need to change the hostname to `k8-worker-<number>` and provide no wifi configuration.
It's also recommended to add the SSH key from the master node to the worker nodes.

On the master node, run the following command to get the SSH key:
```bash
ssh-keygen
```
Get the public key:
```bash
cat ~/.ssh/id_rsa.pub
```
 
### General Setup

1. Update Raspberry Pi OS
```bash
sudo apt update && sudo apt dist-upgrade -y
```

2. Install tools
```bash
sudo apt install -y vim
```

2. Edit the `/boot/firmware/cmdline.txt` file to add config to the end of the line:
```bash
sudo sed -i '$s/$/ cgroup_enable=memory cgroup_memory=1/' /boot/firmware/cmdline.txt
```

3. Add the following lines to `/boot/config.txt` to control PoE fan:
```bash
# PoE Hat Fan Speeds
dtparam=poe_fan_temp0=50000
dtparam=poe_fan_temp1=60000
dtparam=poe_fan_temp2=70000
dtparam=poe_fan_temp3=80000
```

4. On the master node, run `dhcp-lease-list` and find the MAC address of the worker node.

5. On the master node, edit the `/etc/dhcp/dhcpd.conf` file by adding the following lines after the `switch` host`:
```bash
host k8-worker-{N} {
  hardware ethernet <MAC_ADDRESS>;
  fixed-address 192.168.50.{9+N};
}
```
> Replace `{N}` with the number of the worker node and `<MAC_ADDRESS>` with the MAC address of the worker node.
> This is considering that the worker nods will start with the IP address `192.168.50.10`.

6. Add the following line to `/etc/hosts`:
```bash
192.168.50.{9+N} k8-worker-{N}
```
> Replace `{N}` with the number of the worker node and calculate the IP address.

7. Reboot the worker node
```bash
sudo reboot
```

### Setting up Microk8s worker

```bash
1. On the master node, run the following command to get the join command:
```bash
microk8s add-node
```

2. On the worker node, install MicroK8s
```bash
sudo apt install -y snapd
sudo snap install core
sudo snap install microk8s --classic
```

3. Add user to MicroK8s group
```bash
sudo usermod -a -G microk8s $USER
sudo chown -f -R $USER ~/.kube
newgrp microk8s
```

4. Wait MicroK8s to be ready
```bash
microk8s status --wait-ready
```

5. Enable MicroK8s to start on boot by adding the following line to `/etc/rc.local`:
```bash
microk8s start
```
> Make sure to add it before the `exit 0` line.

6. On the worker node, run the join command obtained in step 1.

## Unistalling MicroK8s

Run the following command to uninstall MicroK8s:
```bash
sudo snap remove --purge microk8s && sudo rm -rf ~/.kube
```

