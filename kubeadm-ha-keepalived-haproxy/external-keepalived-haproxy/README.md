# Set up a Highly Available Kubernetes Cluster using kubeadm
Follow this documentation to set up a highly available Kubernetes cluster using __Ubuntu 20.04 LTS__ with keepalived and haproxy

This documentation guides you in setting up a cluster with three master nodes, one worker node and two load balancer node using HAProxy and Keepalived.

## Vagrant Environment
|Role|FQDN|IP|OS|RAM|CPU|
|----|----|----|----|----|----|
|Load Balancer|loadbalancer1.example.com|172.16.16.51|Ubuntu 20.04|512M|1|
|Load Balancer|loadbalancer2.example.com|172.16.16.52|Ubuntu 20.04|512M|1|
|Master|kmaster1.example.com|192.168.15.201|Ubuntu 20.04|2G|2|
|Master|kmaster2.example.com|192.168.15.202|Ubuntu 20.04|2G|2|
|Master|kmaster3.example.com|192.168.15.203|Ubuntu 20.04|2G|2|
|Worker|kworker1.example.com|172.16.16.201|Ubuntu 20.04|2G|2|

> * Password for the **root** account on all these virtual machines is **kubeadmin**
> * Perform all the commands as root user unless otherwise specified

### Virtual IP managed by Keepalived on the load balancer nodes
|Virtual IP|
|----|
|192.168.15.200|

## Pre-requisites
If you want to try this in a virtualized environment on your workstation
* Virtualbox installed
* Vagrant installed
* Host machine has atleast 12 cores
* Host machine has atleast 16G memory

## Bring up all the virtual machines
```
vagrant up
```
If you are on Linux host and want to use KVM/Libvirt
```
vagrant up --provider libvirt
```

## Set up load balancer nodes (loadbalancer1 & loadbalancer2)
##### Install Keepalived & Haproxy
```
apt update && apt install -y keepalived haproxy
```
##### configure keepalived
On both nodes create the health check script /etc/keepalived/check_apiserver.sh
```
cat >> /etc/keepalived/check_apiserver.sh <<EOF
#!/bin/sh

errorExit() {
  echo "*** $@" 1>&2
  exit 1
}

curl --silent --max-time 2 --insecure https://localhost:6443/ -o /dev/null || errorExit "Error GET https://localhost:6443/"
if ip addr | grep -q 192.168.15.200; then
  curl --silent --max-time 2 --insecure https://192.168.15.200:6443/ -o /dev/null || errorExit "Error GET https://192.168.15.200:6443/"
fi
EOF

chmod +x /etc/keepalived/check_apiserver.sh
```
Create keepalived config /etc/keepalived/keepalived.conf
```
cat >> /etc/keepalived/keepalived.conf <<EOF
vrrp_script check_apiserver {
  script "/etc/keepalived/check_apiserver.sh"
  interval 3
  timeout 10
  fall 5
  rise 2
  weight -2
}

vrrp_instance VI_1 {
    state BACKUP
    interface eth0
    virtual_router_id 1
    priority 100
    advert_int 5
    authentication {
        auth_type PASS
        auth_pass mysecret
    }
    virtual_ipaddress {
        192.168.15.200
    }
    track_script {
        check_apiserver
    }
}
EOF
```
##### Enable & start keepalived service
```
systemctl enable --now keepalived
```

##### Configure haproxy
Update **/etc/haproxy/haproxy.cfg**
```
cat >> /etc/haproxy/haproxy.cfg <<EOF

frontend kubernetes-frontend
  bind *:6443
  mode tcp
  option tcplog
  default_backend kubernetes-backend

backend kubernetes-backend
  option httpchk GET /healthz
  http-check expect status 200
  mode tcp
  option ssl-hello-chk
  balance roundrobin
    server cp01 192.168.15.201:6443 check fall 3 rise 2
    server cp02 192.168.15.202:6443 check fall 3 rise 2
    server cp03 192.168.15.203:6443 check fall 3 rise 2

EOF
```
##### Enable & restart haproxy service
```
systemctl enable haproxy && systemctl restart haproxy
```
## Pre-requisites on all kubernetes nodes (masters & workers)
##### Disable swap
```
swapoff -a; sed -i '/swap/d' /etc/fstab
```
##### Disable Firewall
```
systemctl disable --now ufw
```
##### Enable and Load Kernel modules
```
{
cat >> /etc/modules-load.d/containerd.conf <<EOF
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter
}
```
##### Add Kernel settings
```
{
cat >>/etc/sysctl.d/kubernetes.conf<<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system
}
```
##### Install containerd runtime
```
{
  apt update
  apt install -y containerd apt-transport-https
  mkdir /etc/containerd
  containerd config default > /etc/containerd/config.toml
  systemctl restart containerd
  systemctl enable containerd
}
```
##### Add apt repo for kubernetes
```
{
  curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
  apt-add-repository "deb http://apt.kubernetes.io/ kubernetes-xenial main"
}
```
##### Install Kubernetes components
```
{
  apt update
  apt install -y kubeadm=1.22.0-00 kubelet=1.22.0-00 kubectl=1.22.0-00
}
```
## Bootstrap the cluster
## On kmaster1
##### Initialize Kubernetes Cluster
```
kubeadm init --control-plane-endpoint="192.168.15.200:6443" --upload-certs  --pod-network-cidr=10.10.0.0/16
```
Copy the commands to join other master nodes and worker nodes.
##### Deploy Calico network
```
kubectl --kubeconfig=/etc/kubernetes/admin.conf create -f https://docs.projectcalico.org/v3.18/manifests/calico.yaml
```

## Join other master nodes to the cluster
> Use the respective kubeadm join commands you copied from the output of kubeadm init command on the first master.

> IMPORTANT: Don't forget the --apiserver-advertise-address option to the join command when you join the other master nodes.

## Join worker nodes to the cluster
> Use the kubeadm join command you copied from the output of kubeadm init command on the first master


## Downloading kube config to your local machine
On your host machine
```
mkdir ~/.kube
scp root@192.168.15.201:/etc/kubernetes/admin.conf ~/.kube/config
```
Password for root account is kubeadmin (if you used my Vagrant setup)

## Verifying the cluster
```
kubectl cluster-info
kubectl get nodes
```

You can now join any number of the control-plane node running the following command on each as root:

  kubeadm join 192.168.15.200:6443 --token wvw1ci.bh3nflrcenca7i1v \
        --discovery-token-ca-cert-hash sha256:a1e600cc78f94852d0557883230110c65b855ab000a9df59ab08fe12c9329f9e \
        --control-plane --certificate-key d08396311c2c4de5056d6642fd6977868a45e3ce99eb366e697a60f2cc33211c

Please note that the certificate-key gives access to cluster sensitive data, keep it secret!
As a safeguard, uploaded-certs will be deleted in two hours; If necessary, you can use
"kubeadm init phase upload-certs --upload-certs" to reload certs afterward.

Then you can join any number of worker nodes by running the following on each as root:

kubeadm join 192.168.15.200:6443 --token wvw1ci.bh3nflrcenca7i1v \
        --discovery-token-ca-cert-hash sha256:a1e600cc78f94852d0557883230110c65b855ab000a9df59ab08fe12c9329f9e
root@cp01:~# `



kubeadm join 192.168.15.203:6443 --token t0ly51.sny029em6o5sn3j1 \
        --discovery-token-ca-cert-hash sha256:bdd2085baf8ceb4a706e46b1ae86a0eff2a9d5c829a49712c48a18f4cd2c468c