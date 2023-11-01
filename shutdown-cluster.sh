#!/bin/bash

# Stop Microk8s on workers and shutdown
parallel-ssh -i -h ~/.pssh_hosts "/snap/bin/microk8s stop && sudo shutdown now"

# Stop Microk8s on master and shutdown
microk8s stop
sudo shutdown now
