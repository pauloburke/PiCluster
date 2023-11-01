#!/bin/bash

# Stop Microk8s on workers and shutdown
#!/bin/bash

# Stop Microk8s on workers and shutdown
parallel-ssh -h ~/.pssh_hosts "microk8s stop && sudo shutdown now"

# Stop Microk8s on master and shutdown
microk8s stop
sudo shutdown now
