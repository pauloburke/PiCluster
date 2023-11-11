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

First, have a SSD connected to the Raspberry Pi previously formated with ext4.

The following ansible playbook will setup the NFS server with the following configurations:

1. Create a new directory and mount the SSD
2. Add the volume to `/etc/fstab`
3. Install NFS Server
4. Create a mount point for the NFS share (e.g. `/nfs`)
5. Add the NFS share to `/etc/exports`
6. Restart the NFS server

```bash
ansible-playbook -i hosts playbooks/basic_setup/nfs_server_setup.yml
```
> This playbook assumes that the SSD is available at `/dev/sda1`.

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

4. Clone this repo and cd into it
```bash
git clone https://github.com/pauloburke/PiCluster.git
cd PiCluster
```

5. Create cluster issuers for cert-manager
```bash
export CLUSTER_ISSUER_EMAIL=your-email@example.com
envsubst < kubernetes/basic_setup/letsencrypt-cluster-issuer.yml | microk8s kubectl apply -f -
microk8s kubectl apply -f kubernetes/basic_setup/self-signed-cluster-issuer.yml
```
> Make sure to change the email address in the env variable.

7. Add Ingress rule for dashboard
```bash
microk8s kubectl apply -f kubernetes/basic_setup/ingress-kubernetes-dashboard.yml
```
> The dashboard will be available at `https://k8-1`. Make sure that you added the hostname to your `/etc/hosts` file.

8. Get the token to access the dashboard
```bash
microk8s kubectl describe secret -n kube-system microk8s-dashboard-token
```

## Setting up NFS Storage

Instructions obtained from [here](https://microk8s.io/docs/nfs).

1. Install CSI Driver for NFS
```bash
microk8s helm3 repo add csi-driver-nfs https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts
microk8s helm3 repo update
microk8s helm3 install csi-driver-nfs csi-driver-nfs/csi-driver-nfs \
    --namespace kube-system \
    --set kubeletDir=/var/snap/microk8s/common/var/lib/kubelet
```

2. Create the storage class
```bash
export NFS_SERVER_IP=192.168.0.11
envsubst < kubernetes/nfs/storage-class.yml | \
microk8s kubectl apply -f -
```
> Replace `NFS_SERVER_IP` with the IP address of the NFS server.

## Setting up Pi-hole

SSH into the master node and run the following commands:

```bash
mkdir -p /mnt/storage/nfs/pihole/etc
mkdir -p /mnt/storage/nfs/pihole/dnsmasq.d
sudo chown -R nobody:nogroup /mnt/storage/nfs/pihole
sudo chmod -R 777 /mnt/storage/nfs/pihole
cd ~/PiCluster
export PIHOLE_PASSWORD=your-password
microk8s kubectl create namespace pihole
microk8s kubectl apply -f kubernetes/pihole/01-persistent-volume.yml
microk8s kubectl apply -f kubernetes/pihole/02-volume-claim.yml
envsubst < kubernetes/pihole/03-deployment.yml | microk8s kubectl apply -f -
microk8s kubectl apply -f kubernetes/pihole/04-service.yml
```

## Setting up Home Assistant

First enable the following MicroK8s addons:
```bash
microk8s enable community
microk8s enable multus
```

SSH into the master node and run the following commands:

```bash
cd ~/PiCluster
mkdir -p /mnt/storage/nfs/home-assistant
sudo chown -R nobody:nogroup /mnt/storage/nfs/home-assistant
sudo chmod -R 777 /mnt/storage/nfs/home-assistant
export HOMEASSISTANT_BASE64_CONFIG=$(base64 -w 0 kubernetes/home-assistant/configuration.yml)
microk8s kubectl create namespace home-assistant
microk8s kubectl apply -f kubernetes/home-assistant/volume-claim.yml
envsubst < kubernetes/home-assistant/secret.yml | microk8s kubectl apply -f -
microk8s kubectl apply -f kubernetes/home-assistant/network-attachment.yml
microk8s kubectl apply -f kubernetes/home-assistant/deployment.yml
microk8s kubectl apply -f kubernetes/home-assistant/service.yml
microk8s kubectl apply -f kubernetes/home-assistant/ingress.yml
```

## Unistalling MicroK8s

Run the following command to uninstall MicroK8s:
```bash
sudo snap remove --purge microk8s && sudo rm -rf ~/.kube
```

