# PiCluster
Code and Documentation for setting up a RaspberryPi Cluster


## Installing Ubuntu Server image on SD Card

1. Download Ubuntu Server for Raspberry Pi from this [link](https://ubuntu.com/download/raspberry-pi) (Used version 22.04.3 LTS at the time of writing).
2. Follow the steps on this [tutorial](https://ubuntu.com/tutorials/how-to-install-ubuntu-on-your-raspberry-pi) to write the image to an SD card.
    > Make sure you edit the install configuration by setting up a hostname, user, and wifi connections if necessary.

    > :warning: **The master node must be named "k8-master" for the Kubernetes Dashboard Ingress rule to work. Otherwise, you will have to change the host name in the ingress rule.**

## Setting up common configurations for Master and Workers

1. Update Ubuntu

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

3. Reboot
```bash
sudo reboot
```

4. Install MicroK8s
```bash
sudo snap install microk8s --classic

```

5. Open firewall for Kubernetes pods to communicate with each other and the internet:
```bash
sudo ufw allow in on cni0 && sudo ufw allow out on cni0
sudo ufw default allow routed
```

6. Add user to MicroK8s group
```bash
sudo usermod -a -G microk8s $USER
sudo chown -f -R $USER ~/.kube
newgrp microk8s
```

7. Wait MicroK8s to be ready
```bash
microk8s status --wait-ready
```

## Setting up Master Node

1. Enable MicroK8s addons
```bash
microk8s enable dns 
microk8s enable hostpath-storage
microk8s enable ingress
microk8s enable helm
microk8s enable dashboard
```

8. Wait for pods to be ready
```bash
watch -n 1 microk8s kubectl get all --all-namespaces
```
> If ingress fails to start, reboot the server.

9. Add Ingress rule for dashboard
```bash
microk8s kubectl apply -f ingress-kubernetes-dashboard.yaml
```
> This file is in the repo.

10. Get the token to access the dashboard
```bash
microk8s kubectl describe secret -n kube-system microk8s-dashboard-token
```

11. (Optional) If calico-node keeps restarting (`Readiness probe failed: calico/node is not ready: felix is not ready: readiness probe reporting 503`), you might have to upgrade the "conmon" package (v1.0.27+):
```bash
wget https://launchpad.net/ubuntu/+source/conmon/2.1.6+ds1-1/+build/25582274/+files/conmon_2.1.6+ds1-1_arm64.deb
sudo dpkg -i conmon_2.1.6+ds1-1_arm64.deb
rm conmon_2.1.6+ds1-1_arm64.deb
```

## Unistalling MicroK8s

Run the following command to uninstall MicroK8s:
```bash
sudo snap remove --purge microk8s && sudo rm -rf ~/.kube
```

