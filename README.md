# PiCluster

Code and Documentation for setting up a RaspberryPi Cluster

## Setting Master

### Installing Raspberry Pi OS

1. Download the Raspberry Pi Imager from [here](https://www.raspberrypi.org/software/).
2. Open the Raspberry Pi Imager and select the Raspberry Pi OS Lite (64-bit) option for Operating System.
3. Select the SD card you want to use and click on "Next".
4. Edit the configurations setting the hostname to `k8-master`, wifi configuration, and enabling SSH.
5. Write the image to the SD card.

### General Setup

1. Update Raspberry Pi OS

```bash
sudo apt update && sudo apt dist-upgrade -y
```

2. Add the following configuration:
```bash
sudo vim /boot/firmware/cmdline.txt
```
Add the following to the end of the line:
```bash
cgroup_enable=memory cgroup_memory=1
```

3. Install tools
```bash
sudo apt install -y vim git curl wget pssh
```

4. Reboot the server
```bash
sudo reboot
```

### Setting up DHCP Server

1. Install DHCP Server
```bash
sudo apt install -y isc-dhcp-server
```

2. Find the MAC address of the master node `eth0` interface:
```bash
ip link show eth0
```

2. Edit the `/etc/dhcp/dhcpd.conf` file by commenting all lines and adding the following lines to the end of the file:
```bash
ddns-update-style none;
authoritative;
log-facility local7;

# No service will be given on this subnet
subnet 192.168.1.0 netmask 255.255.255.0 {
}

# The internal cluster network
group {
   option broadcast-address 192.168.50.255;
   option routers 192.168.50.1;
   default-lease-time 600;
   max-lease-time 7200;
   option domain-name "k8-master";
   option domain-name-servers 8.8.8.8, 8.8.4.4;
   subnet 192.168.50.0 netmask 255.255.255.0 {
      range 192.168.50.20 192.168.50.250;

      # Head Node
      host k8-master {
         hardware ethernet <MAC_ADDRESS>;
         fixed-address 192.168.50.1;
      }

   }
}
```

3. Edit the `/etc/default/isc-dhcp-server` file:
```bash
INTERFACESv4="eth0"
```

5. Restart the DHCP server:
```bash
sudo systemctl restart isc-dhcp-server.service
```

6. If your is managed, it will be assigned an IP address after a few moments. Check if it shows up in the leases file:
```bash
dhcp-lease-list
```

7. Set an static IP address for the switch by adding the following lines to `/etc/dhcp/dhcpd.conf` after the `k8-master` host:
```bash
host switch {
  hardware ethernet <MAC_ADDRESS>;
  fixed-address 192.168.50.254;
}
```

8. Restart the DHCP server:
```bash
sudo systemctl restart isc-dhcp-server.service
```
> It will not show up in the leases file anymore once it has a static IP address.

### Setting up NFS Server

Considering that a SSD is plugged into the master node, we will use it to store the data for the cluster.

1. Check the name of the SSD:
```bash
sudo fdisk -l
```
> In my case, the SSD was named `/dev/sda`.

2. Create a new partition on the SSD:
```bash
sudo parted -s /dev/sda mklabel gpt
sudo parted --a optimal /dev/sda mkpart primary ext4 0% 100%
sudo mkfs -t ext4 /dev/sda1
```

3. Create a new directory and mount the SSD:
```bash
sudo mkdir /mnt/ssd
sudo mount /dev/sda1 /mnt/ssd
```

4. Add the following line to `/etc/fstab`:
```bash
/dev/sda1 /mnt/ssd ext4 defaults,user 0 1
```

5. Install NFS Server:
```bash
sudo apt install -y nfs-kernel-server
```

6. Create a mount point for the NFS share:
```bash
sudo mkdir /mnt/ssd/nfs
sudo chown <user>:<user> /mnt/ssd/nfs
sudo ln -s /mnt/ssd/nfs /nfs
```

7. Add the following line to `/etc/exports`:
```bash
/nfs 192.168.50.0/24(rw,sync)
```

8. Restart the NFS server:
```bash
sudo systemctl enable rpcbind.service
sudo systemctl start rpcbind.service
sudo systemctl enable nfs-server.service
sudo systemctl start nfs-server.service
```

### Setting up MicroK8s

1. Install MicroK8s
```bash
sudo apt install -y snapd
sudo snap install core
sudo snap install microk8s --classic
```

2. Add user to MicroK8s group
```bash
sudo usermod -a -G microk8s $USER
sudo chown -f -R $USER ~/.kube
newgrp microk8s
```

3. Wait MicroK8s to be ready
```bash
microk8s status --wait-ready
```

4. Enable MicroK8s addons
```bash
microk8s enable dns 
microk8s enable ingress
microk8s enable helm
microk8s enable dashboard
microk8s enable cert-manager
```

5. Wait for pods to be ready
```bash
watch -n 1 microk8s kubectl get all --all-namespaces
```
> If ingress fails to start, reboot the server.

6. Clone this repo
```bash
git clone https://github.com/pauloburke/PiCluster.git
```

7. Add Ingress rule for dashboard
```bash
microk8s kubectl apply -f PiCluster/ingress-kubernetes-dashboard.yaml
```
> This file is in the repo.

8. Get the token to access the dashboard
```bash
microk8s kubectl describe secret -n kube-system microk8s-dashboard-token
```

9. Create cluster issuer for cert-manager
```bash
microk8s kubectl apply -f PiCluster/cluster-issuer.yml
```
> Make sure to change the email address in the file.
<!-- Change to email env variable -->

14. Create a NFS storage class
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

3. On the master node, run `dhcp-lease-list` and find the MAC address of the worker node.

4. On the master node, edit the `/etc/dhcp/dhcpd.conf` file by adding the following lines after the `switch` host`:
```bash
host k8-worker-{N} {
  hardware ethernet <MAC_ADDRESS>;
  fixed-address 192.168.50.{9+N};
}
```
> Replace `{N}` with the number of the worker node and `<MAC_ADDRESS>` with the MAC address of the worker node.
> This is considering that the worker nods will start with the IP address `192.168.50.10`.

5. Add the following line to `/etc/hosts`:
```bash
192.168.50.{9+N} k8-worker-{N}
```
> Replace `{N}` with the number of the worker node and calculate the IP address.

3. Reboot the worker node
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

5. On the worker node, run the join command obtained in step 1.

## Unistalling MicroK8s

Run the following command to uninstall MicroK8s:
```bash
sudo snap remove --purge microk8s && sudo rm -rf ~/.kube
```

