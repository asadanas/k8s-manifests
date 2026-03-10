# Kubernetes HA Cluster Installation Guide (3 Masters + 3 Workers)
## Cluster Topology
```
HAProxy Load Balancer 
│
├── Master Nodes (control plane)
│   ├── master1 
│   ├── master2 
│   └── master3 
│
└── Worker Nodes
    ├── worker1 
    ├── worker2 
    └── worker3 
```
>  Important: HAProxy ONLY load-balances Kubernetes API server (port 6443). Ingress traffic (HTTP/HTTPS) is handled by nginx-ingress controller inside the cluster.

## PHASE 1: PREPARE ALL NODES (Masters + Workers)
### Step 1.1: Disable Swap (ALL NODES)

#### Disable immediately
```bash
sudo swapoff -a
```
#### Prevent reactivation on reboot
```bash
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
```
#### Verify swap is off
```bash
free -h | grep Swap  # Should show 0B
```
### Step 1.2: Load Kernel Modules (ALL NODES)
#### Load modules immediately
```bash
sudo modprobe br_netfilter
sudo modprobe overlay

# Persist across reboots
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

# Apply sysctl settings
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system
```

### Step 1.3: Install containerd (ALL NODES)
#### Install containerd
```bash
sudo apt update
sudo apt install -y containerd
```
#### Configure containerd
```bash
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
```
#### Enable systemd cgroup driver (CRITICAL FOR K8S)
```bash
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
```
#### Restart containerd
```bash
sudo systemctl restart containerd
sudo systemctl enable containerd

# Verify
sudo containerd --version
```
### Step 1.4: Install Kubernetes Components (ALL NODES)
#### Add Kubernetes GPG key (FIXED URL - NO SPACES)
```bash
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
```
#### Add Kubernetes repository (FIXED URL)
```bash
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list
```
#### Install components
```bash
sudo apt update
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
```
#### Start kubelet
```bash
sudo systemctl enable --now kubelet
```
#### Verify
```bash
kubeadm version
```
## PHASE 2: CONFIGURE HAProxy LOAD BALANCER
### Run these steps on your dedicated HAProxy server
### Step 2.1: Install HAProxy
```bash
sudo apt update
sudo apt install -y haproxy
```
### Step 2.2: Configure HAProxy (/etc/haproxy/haproxy.cfg)
```bash
vim /etc/haproxy/haproxy.cfg
```
#### Past the following configuration here. 
```bash
global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon
    maxconn 2000

defaults
    log global
    mode tcp
    option dontlognull
    timeout connect 5s
    timeout client  50s
    timeout server  50s
    retries 3

# ONLY load balance Kubernetes API server (port 6443)
frontend k8s_api
    bind *:6443
    mode tcp
    default_backend k8s_masters

backend k8s_masters
    mode tcp
    balance roundrobin
    option tcp-check
    server master1 <master1_IP>:6443 check
    server master2 <master2_IP>:6443 check
    server master3 <master3_IP>:6443 check
```
### Step 2.3: Restart HAProxy
```bash
sudo systemctl restart haproxy
sudo systemctl enable haproxy
```
#### Verify HAProxy is listening on 6443
```bash
sudo ss -tulpn | grep 6443
```
## PHASE 3: INITIALIZE FIRST CONTROL PLANE NODE (master1)

### Step 3.1: Initialize Cluster
#### Run on master1 ONLY
```bash
sudo kubeadm init \
  --control-plane-endpoint "<LoadBalancer_IP>:6443" \
  --upload-certs \
  --pod-network-cidr=192.168.0.0/16 \ # You can define any private range IP
  --apiserver-advertise-address=<master1_IP>
```
#### Expected output:
Your Kubernetes control-plane has initialized successfully!
SAVE THE JOIN COMMANDS shown at the end (you'll need them for other nodes)

### Step 3.2: Configure kubectl
```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```
### Step 3.3: Install Calico CNI
```bash
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml
```
#### Verify Calico pods are running (takes 1-2 minutes)
```bash
watch kubectl get pods -n kube-system -l k8s-app=calico-node
```
#### Press Ctrl+C when all show STATUS=Running

### Step 3.4: Verify Control Plane
```bash
kubectl get nodes
```
#### Should show master1 in "NotReady" state (will become Ready after Calico pods run)
```bash
kubectl get pods -n kube-system
```
#### Verify: CoreDNS pods should be Running (not CrashLoopBackOff)

## PHASE 4: JOIN ADDITIONAL CONTROL PLANE NODES (master2, master3)

### Step 4.1: Generate Certificate Key (on master1)
#### Get certificate key from first master
```bash
CERT_KEY=$(sudo kubeadm init phase upload-certs --upload-certs | grep -A1 'certificate key:' | tail -1 | tr -d '[:space:]')

echo "Certificate Key: $CERT_KEY"
```
### Step 4.2: Join Second Master (on master2)
#### Use the join command from Step 3.1 output, ADDING:
#### --control-plane --certificate-key <CERT_KEY>
```bash
sudo kubeadm join <LoadBalancer_IP>:6443 \
  --token <YOUR_TOKEN> \
  --discovery-token-ca-cert-hash sha256:<YOUR_HASH> \
  --control-plane \
  --certificate-key $CERT_KEY \
  --apiserver-advertise-address=<master2_IP>
```
### Step 4.3: Configure kubectl on master2
```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```
### Step 4.4: Repeat for master3

### Step 4.5: Verify Multi-Master Cluster (on any master)
```bash
kubectl get nodes
```
#### Should show 3 master nodes in "Ready" state
```bash
kubectl get pods -n kube-system -l component=etcd
```
#### Should show 3 etcd pods (one per master)

## PHASE 5: JOIN WORKER NODES (worker1, worker2, worker3)
### Step 5.1: Join Worker Nodes
#### Use the WORKER join command from Step 3.1 output (without --control-plane flags)
#### Run on each worker node:
```bash
sudo kubeadm join <LoadBalancer_IP>:6443 \
  --token <YOUR_TOKEN> \
  --discovery-token-ca-cert-hash sha256:<YOUR_HASH>
```

