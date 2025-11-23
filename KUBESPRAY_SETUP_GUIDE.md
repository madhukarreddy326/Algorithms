# Kubespray Setup Guide for On-Premises VMs
## With Calico CNI and Containerd Runtime

---

## Table of Contents
1. [Overview](#overview)
2. [Key Concepts to Understand](#key-concepts-to-understand)
3. [Prerequisites](#prerequisites)
4. [Step-by-Step Setup](#step-by-step-setup)
5. [Configuration Deep Dive](#configuration-deep-dive)
6. [Troubleshooting](#troubleshooting)
7. [Post-Installation Verification](#post-installation-verification)

---

## Overview

**Kubespray** is an Ansible-based tool that provides production-ready Kubernetes clusters. This guide focuses on:
- **Container Runtime**: containerd (lightweight, production-grade)
- **CNI Plugin**: Calico (network policy enforcement and networking)
- **Environment**: On-premises VMs

---

## Key Concepts to Understand

### 1. **Kubespray Architecture**
- Uses Ansible playbooks to automate Kubernetes deployment
- Supports various CNI plugins and container runtimes
- Highly customizable through inventory files
- Idempotent operations (safe to re-run)

### 2. **Calico CNI**
- Layer 3 networking solution
- Provides network policy enforcement
- Uses BGP for routing (optional)
- Supports both overlay (VXLAN/IPIP) and non-overlay modes
- **Key Decision**: Choose between IPIP, VXLAN, or no encapsulation

### 3. **Containerd**
- Industry-standard container runtime
- More lightweight than Docker
- Direct integration with Kubernetes (CRI)
- Better performance and resource usage

### 4. **Kubernetes Components You'll Deploy**
- **Control Plane**: API Server, Scheduler, Controller Manager, etcd
- **Worker Nodes**: kubelet, kube-proxy
- **Add-ons**: CoreDNS, metrics-server (optional)

---

## Prerequisites

### 1. **Infrastructure Requirements**

#### Minimum VM Specifications:
```
Control Plane Nodes (Master):
- CPU: 2+ cores
- RAM: 4GB minimum, 8GB recommended
- Disk: 50GB+
- Network: Static IP recommended

Worker Nodes:
- CPU: 2+ cores  
- RAM: 4GB minimum, 8GB+ for workloads
- Disk: 50GB+ (depends on workload)
- Network: Static IP recommended

Etcd Nodes (if separate):
- CPU: 2+ cores
- RAM: 8GB+
- Disk: 50GB+ SSD preferred
```

#### Number of Nodes:
- **Development**: 1 master + 2 workers (minimum)
- **Production**: 3 masters + 3+ workers
- **High Availability**: Odd number of control plane nodes (3, 5, 7)

### 2. **Operating System Requirements**

**Supported OS** (Choose one):
- Ubuntu 20.04/22.04 LTS (Recommended)
- Debian 10/11
- CentOS/RHEL 7/8
- Rocky Linux 8/9

**OS Configuration**:
```bash
# Disable swap (Required for Kubernetes)
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# Disable firewall or configure ports (Option 1: Disable)
sudo systemctl stop firewalld
sudo systemctl disable firewalld

# Or configure required ports (Option 2: Configure)
# See Port Requirements section below
```

### 3. **Network Requirements**

#### Network Prerequisites:
- **All nodes must communicate with each other** (no firewall blocking)
- **Static IPs or DHCP reservations** for all nodes
- **DNS resolution** between all nodes
- **Internet access** for package downloads (or local mirror)

#### Required Ports:

**Control Plane Nodes**:
```
6443        - Kubernetes API Server
2379-2380   - etcd server client API
10250       - kubelet API
10251       - kube-scheduler
10252       - kube-controller-manager
10255       - Read-only kubelet API
```

**Worker Nodes**:
```
10250       - kubelet API
30000-32767 - NodePort Services
```

**Calico Specific**:
```
179         - BGP (if using BGP)
4789        - VXLAN (if using VXLAN encapsulation)
```

#### Network Design Decisions:
- **Pod CIDR**: Default 10.233.64.0/18 (can customize)
- **Service CIDR**: Default 10.233.0.0/18 (can customize)
- **Ensure no overlap** with existing network infrastructure

### 4. **Ansible Control Node Requirements**

One machine (can be your laptop/workstation) to run Ansible:

```bash
# Required on Ansible control node (not cluster nodes):
- Python 3.8+
- Ansible 2.11+
- pip3
- SSH access to all cluster nodes
- SSH key-based authentication (no password)
```

### 5. **SSH Setup**

**Critical Prerequisite**:

```bash
# On Ansible control node, generate SSH key if not exists
ssh-keygen -t rsa -b 4096

# Copy SSH key to ALL cluster nodes
ssh-copy-id user@<node-ip>

# Test SSH access (should not ask for password)
ssh user@<node-ip>

# Ensure user has sudo privileges without password
# On each cluster node, edit sudoers:
echo "username ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/username
```

### 6. **DNS/Hostname Setup**

```bash
# On each node, set unique hostname
sudo hostnamectl set-hostname <unique-name>

# Update /etc/hosts on all nodes (or use DNS)
# Example /etc/hosts:
192.168.1.10 master1 master1.example.com
192.168.1.11 master2 master2.example.com
192.168.1.12 master3 master3.example.com
192.168.1.20 worker1 worker1.example.com
192.168.1.21 worker2 worker2.example.com
192.168.1.22 worker3 worker3.example.com
```

---

## Step-by-Step Setup

### **Phase 1: Prepare Ansible Control Node**

#### Step 1: Install Dependencies
```bash
# Ubuntu/Debian
sudo apt update
sudo apt install -y python3 python3-pip git

# CentOS/RHEL
sudo yum install -y python3 python3-pip git
```

#### Step 2: Clone Kubespray Repository
```bash
cd ~
git clone https://github.com/kubernetes-sigs/kubespray.git
cd kubespray

# Checkout stable version (check latest release)
git checkout release-2.24  # Use latest stable release
```

#### Step 3: Install Python Requirements
```bash
# Install requirements
pip3 install -r requirements.txt

# Verify Ansible installation
ansible --version  # Should show 2.11+
```

### **Phase 2: Configure Inventory**

#### Step 4: Create Inventory Directory
```bash
# Copy sample inventory
cp -rfp inventory/sample inventory/mycluster

# Navigate to your inventory
cd inventory/mycluster
```

#### Step 5: Configure Inventory File

**Edit `inventory/mycluster/inventory.ini`**:

```ini
# Example inventory for 3 masters + 3 workers

[all]
master1 ansible_host=192.168.1.10 ip=192.168.1.10
master2 ansible_host=192.168.1.11 ip=192.168.1.11
master3 ansible_host=192.168.1.12 ip=192.168.1.12
worker1 ansible_host=192.168.1.20 ip=192.168.1.20
worker2 ansible_host=192.168.1.21 ip=192.168.1.21
worker3 ansible_host=192.168.1.22 ip=192.168.1.22

[kube_control_plane]
master1
master2
master3

[etcd]
master1
master2
master3

[kube_node]
worker1
worker2
worker3

[calico_rr]
# Leave empty unless using BGP route reflectors

[k8s_cluster:children]
kube_control_plane
kube_node
calico_rr
```

**Alternative: Generate inventory using script**:
```bash
# For simpler setups
declare -a IPS=(192.168.1.10 192.168.1.11 192.168.1.20 192.168.1.21)
CONFIG_FILE=inventory/mycluster/hosts.yaml python3 contrib/inventory_builder/inventory.py ${IPS[@]}
```

### **Phase 3: Configure Kubespray Variables**

#### Step 6: Configure Container Runtime (containerd)

**Edit `inventory/mycluster/group_vars/all/all.yml`**:

```yaml
# Container runtime
container_manager: containerd  # Use containerd

# Download settings
download_run_once: true
download_localhost: false

# Registry settings (optional - for offline/air-gapped)
# registry_host: "registry.example.com:5000"
# files_repo: "http://your-local-repo.com"
```

**Edit `inventory/mycluster/group_vars/all/containerd.yml`** (optional tuning):

```yaml
# Containerd settings
containerd_use_systemd_cgroup: true
containerd_default_runtime: "runc"

# Storage configuration
containerd_storage_dir: "/var/lib/containerd"
containerd_state_dir: "/run/containerd"
```

#### Step 7: Configure Calico CNI

**Edit `inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml`**:

```yaml
# Network plugin
kube_network_plugin: calico  # Use Calico

# Network CIDR settings
kube_service_addresses: 10.233.0.0/18
kube_pods_subnet: 10.233.64.0/18

# DNS configuration
dns_mode: coredns
enable_nodelocaldns: true  # Recommended for performance

# Kubernetes version
kube_version: v1.28.5  # Check latest stable version
```

**Edit `inventory/mycluster/group_vars/k8s_cluster/k8s-net-calico.yml`**:

```yaml
# Calico Network Configuration

# IP-in-IP encapsulation mode
# Options: "Always", "CrossSubnet", "Never"
calico_ipip_mode: "Always"  # Start with Always, optimize later

# VXLAN encapsulation (alternative to IPIP)
# Set to "Always" if IPIP doesn't work in your environment
calico_vxlan_mode: "Never"  # Use IPIP by default

# BGP configuration
calico_node_to_node_mesh: true  # Enable BGP mesh
# peer_with_router: false  # Enable if peering with physical routers

# Network policy
calico_network_policy_enabled: true  # Enable network policies

# MTU configuration (adjust based on your network)
calico_mtu: 1440  # Adjust if using VXLANs/overlays (typically 1440-1500)

# Calico version (usually auto-set by kubespray)
# calico_version: "v3.26.1"

# Performance tuning
calico_felix_prometheusmetricsenabled: true
```

**Important Calico Configuration Choices**:

1. **Encapsulation Mode**:
   - `IPIP Always`: Works everywhere, slight overhead
   - `IPIP CrossSubnet`: Encapsulation only when crossing subnets (recommended if your VMs are in different subnets)
   - `IPIP Never`: No encapsulation, best performance (requires BGP or L2 network)

2. **BGP vs Overlay**:
   - **BGP** (calico_vxlan_mode: "Never", calico_ipip_mode: "Never"): Best performance, requires network support
   - **Overlay** (IPIP/VXLAN): Works on any network, slight performance overhead

3. **MTU Size**:
   - Standard network: 1500
   - With VXLAN: 1450
   - With IPIP: 1480
   - Cloud environments: Check provider specs

### **Phase 4: Additional Configuration**

#### Step 8: Configure Additional Features

**Edit `inventory/mycluster/group_vars/k8s_cluster/addons.yml`**:

```yaml
# Metrics server (recommended)
metrics_server_enabled: true

# Ingress controller (optional)
ingress_nginx_enabled: false  # Enable if needed

# Helm (optional)
helm_enabled: true  # Recommended for package management

# Cert manager (optional)
cert_manager_enabled: false  # Enable for TLS certificate management

# Dashboard (optional, not recommended for production)
dashboard_enabled: false
```

#### Step 9: Configure Cluster Settings

**Edit `inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml`** (additional settings):

```yaml
# API server settings
kube_apiserver_enable_admission_plugins:
  - NodeRestriction
  - PodSecurityPolicy  # Optional, for pod security
  
# Certificate validity
certificates_duration: 36500  # 100 years (default)

# Kubelet configuration
kubelet_max_pods: 110  # Pods per node

# Enable audit logging (optional)
kubernetes_audit: false

# Cluster name
cluster_name: mycluster
```

### **Phase 5: Pre-flight Validation**

#### Step 10: Validate Configuration

```bash
# Test Ansible connectivity to all nodes
ansible -i inventory/mycluster/inventory.ini all -m ping -u <your-ssh-user>

# Expected output: All nodes show "pong"

# Check sudo access
ansible -i inventory/mycluster/inventory.ini all -m shell -a "sudo whoami" -u <your-ssh-user>

# Expected output: "root" from all nodes
```

#### Step 11: Pre-flight Checks Script

Create a validation script:

```bash
# Create preflight-check.sh
cat > preflight-check.sh << 'EOF'
#!/bin/bash

echo "=== Kubespray Pre-flight Checks ==="

# Check swap
echo "Checking swap status..."
ansible -i inventory/mycluster/inventory.ini all -m shell -a "free | grep Swap"

# Check firewall
echo "Checking firewall..."
ansible -i inventory/mycluster/inventory.ini all -m shell -a "systemctl status firewalld || systemctl status ufw"

# Check SELinux (CentOS/RHEL)
echo "Checking SELinux..."
ansible -i inventory/mycluster/inventory.ini all -m shell -a "getenforce" 2>/dev/null || echo "SELinux not present"

# Check disk space
echo "Checking disk space..."
ansible -i inventory/mycluster/inventory.ini all -m shell -a "df -h /"

# Check network connectivity
echo "Checking network connectivity..."
ansible -i inventory/mycluster/inventory.ini all -m shell -a "ping -c 2 8.8.8.8"

echo "=== Pre-flight checks complete ==="
EOF

chmod +x preflight-check.sh
./preflight-check.sh
```

### **Phase 6: Deploy Kubernetes Cluster**

#### Step 12: Run Kubespray Playbook

```bash
# Navigate to kubespray directory
cd ~/kubespray

# Run the cluster deployment playbook
# This will take 15-30 minutes depending on your environment
ansible-playbook -i inventory/mycluster/inventory.ini cluster.yml \
  -u <your-ssh-user> \
  -b \
  --become-user=root

# If using SSH key with passphrase:
ansible-playbook -i inventory/mycluster/inventory.ini cluster.yml \
  -u <your-ssh-user> \
  -b \
  --become-user=root \
  --ask-pass

# For verbose output (debugging):
ansible-playbook -i inventory/mycluster/inventory.ini cluster.yml \
  -u <your-ssh-user> \
  -b \
  --become-user=root \
  -vvv
```

**What the playbook does**:
1. Prepares all nodes (installs packages, configures system)
2. Installs and configures containerd
3. Installs etcd cluster
4. Deploys Kubernetes control plane
5. Installs Calico CNI
6. Joins worker nodes
7. Configures kubectl access

#### Step 13: Monitor Deployment

Watch the deployment progress. Common stages:
- Download and install packages
- Configure container runtime
- Bootstrap etcd cluster
- Deploy Kubernetes control plane
- Install network plugin (Calico)
- Join worker nodes
- Deploy add-ons

**Troubleshooting during deployment**:
- If a task fails, check the error message
- You can re-run the playbook (it's idempotent)
- Check logs on specific nodes if needed

---

## Configuration Deep Dive

### Understanding Kubespray Directory Structure

```
kubespray/
├── inventory/
│   └── mycluster/
│       ├── inventory.ini          # Node inventory
│       └── group_vars/
│           ├── all/               # Variables for all nodes
│           │   ├── all.yml
│           │   └── containerd.yml
│           └── k8s_cluster/       # Kubernetes-specific vars
│               ├── k8s-cluster.yml
│               ├── k8s-net-calico.yml
│               └── addons.yml
├── cluster.yml                    # Main deployment playbook
├── reset.yml                      # Cluster removal playbook
└── scale.yml                      # Scale cluster (add nodes)
```

### Key Configuration Files Explained

#### 1. **inventory.ini**
- Defines your cluster topology
- Maps IPs to roles (master, worker, etcd)
- Ansible connection details

#### 2. **all.yml**
- Global settings affecting all nodes
- Container runtime selection
- Download/registry configuration

#### 3. **k8s-cluster.yml**
- Core Kubernetes settings
- Network plugin choice
- Pod/Service CIDR ranges
- Kubernetes version

#### 4. **k8s-net-calico.yml**
- Calico-specific configuration
- Encapsulation mode
- BGP settings
- Network policies

### Advanced Calico Configurations

#### Option 1: IPIP with CrossSubnet (Recommended for Multi-Subnet)

```yaml
# k8s-net-calico.yml
calico_ipip_mode: "CrossSubnet"
calico_vxlan_mode: "Never"
calico_network_backend: "bird"
```

**Use when**: Your nodes are in different subnets

#### Option 2: VXLAN (Alternative Overlay)

```yaml
# k8s-net-calico.yml
calico_ipip_mode: "Never"
calico_vxlan_mode: "Always"
calico_network_backend: "vxlan"
```

**Use when**: IPIP is blocked by network or running on Windows nodes

#### Option 3: No Encapsulation (Best Performance)

```yaml
# k8s-net-calico.yml
calico_ipip_mode: "Never"
calico_vxlan_mode: "Never"
calico_network_backend: "bird"
peer_with_router: true  # If peering with physical routers
```

**Use when**: You have full control of network infrastructure and can route pod IPs

---

## Post-Installation Verification

### Step 14: Access Your Cluster

```bash
# SSH to any master node
ssh user@master1

# Check cluster status
kubectl get nodes

# Expected output: All nodes in Ready state
# NAME      STATUS   ROLES           AGE   VERSION
# master1   Ready    control-plane   10m   v1.28.5
# master2   Ready    control-plane   10m   v1.28.5
# master3   Ready    control-plane   10m   v1.28.5
# worker1   Ready    <none>          9m    v1.28.5
# worker2   Ready    <none>          9m    v1.28.5
# worker3   Ready    <none>          9m    v1.28.5
```

### Step 15: Copy kubeconfig to Local Machine

```bash
# From Ansible control node, copy kubeconfig
ssh user@master1 "sudo cat /etc/kubernetes/admin.conf" > ~/.kube/config

# OR copy from the generated artifacts (Kubespray creates it)
# Check: ~/kubespray/inventory/mycluster/artifacts/

# Set proper permissions
chmod 600 ~/.kube/config

# Test from local machine
kubectl get nodes
```

### Step 16: Verify Components

```bash
# Check all system pods
kubectl get pods -n kube-system

# Expected pods:
# - calico-node (daemonset - one per node)
# - calico-kube-controllers
# - coredns
# - kube-apiserver (on control plane)
# - kube-controller-manager (on control plane)
# - kube-scheduler (on control plane)
# - kube-proxy (daemonset - one per node)
# - nodelocaldns (daemonset - if enabled)

# Check component status
kubectl get componentstatuses  # Deprecated but still useful

# Check etcd health (from master node)
sudo ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/ssl/etcd/ssl/ca.pem \
  --cert=/etc/ssl/etcd/ssl/node-master1.pem \
  --key=/etc/ssl/etcd/ssl/node-master1-key.pem \
  endpoint health
```

### Step 17: Verify Calico

```bash
# Check Calico pods
kubectl get pods -n kube-system -l k8s-app=calico-node

# Check Calico status (from any node)
sudo calicoctl node status

# Install calicoctl if not present:
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/calicoctl.yaml

# Check BGP peers (if using BGP)
kubectl exec -n kube-system <calico-node-pod> -- calicoctl node status

# Verify IP pool
kubectl get ippools -o wide
```

### Step 18: Verify Containerd

```bash
# SSH to any node
ssh user@worker1

# Check containerd status
sudo systemctl status containerd

# List containers (using crictl)
sudo crictl ps

# Check containerd config
sudo cat /etc/containerd/config.toml

# Test container runtime
sudo crictl version
```

### Step 19: Deploy Test Application

```bash
# Create test deployment
kubectl create deployment nginx --image=nginx:latest

# Expose as service
kubectl expose deployment nginx --port=80 --type=NodePort

# Check deployment
kubectl get pods
kubectl get svc

# Test connectivity
curl http://<any-node-ip>:<nodeport>

# Cleanup
kubectl delete deployment nginx
kubectl delete service nginx
```

### Step 20: Test Network Policies (Calico Feature)

```yaml
# Create test network policy
cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: test-netpol
---
apiVersion: v1
kind: Pod
metadata:
  name: nginx
  namespace: test-netpol
  labels:
    app: nginx
spec:
  containers:
  - name: nginx
    image: nginx:latest
    ports:
    - containerPort: 80
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
  namespace: test-netpol
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
EOF

# Verify policy is applied
kubectl get networkpolicy -n test-netpol

# Test (should fail due to policy)
kubectl run -it --rm --restart=Never test --image=busybox -n test-netpol -- wget -O- http://nginx.test-netpol

# Cleanup
kubectl delete namespace test-netpol
```

---

## Troubleshooting

### Common Issues and Solutions

#### 1. **Nodes Not Ready**

```bash
# Check node status
kubectl describe node <node-name>

# Common causes:
# - Container runtime not running
# - CNI plugin issues
# - Firewall blocking ports

# Check kubelet logs (on the problematic node)
sudo journalctl -u kubelet -f

# Check containerd
sudo systemctl status containerd
sudo journalctl -u containerd -f
```

#### 2. **Calico Pods Not Starting**

```bash
# Check Calico pod logs
kubectl logs -n kube-system <calico-node-pod>

# Common issues:
# - IP pool misconfiguration
# - Network interface issues
# - Kernel module missing

# Check network interfaces
ip addr show

# Verify iptables rules
sudo iptables -L -n -v -t nat
```

#### 3. **DNS Not Working**

```bash
# Test DNS from a pod
kubectl run -it --rm --restart=Never test --image=busybox -- nslookup kubernetes.default

# Check CoreDNS pods
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Check CoreDNS logs
kubectl logs -n kube-system -l k8s-app=kube-dns
```

#### 4. **Etcd Issues**

```bash
# Check etcd pods (if using static pods)
kubectl get pods -n kube-system | grep etcd

# Check etcd logs (on master node)
sudo journalctl -u etcd -f

# Verify etcd cluster health
sudo ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/ssl/etcd/ssl/ca.pem \
  --cert=/etc/ssl/etcd/ssl/node-$(hostname).pem \
  --key=/etc/ssl/etcd/ssl/node-$(hostname)-key.pem \
  member list
```

#### 5. **Kubespray Playbook Fails**

```bash
# Re-run with verbose output
ansible-playbook -i inventory/mycluster/inventory.ini cluster.yml -u <user> -b -vvv

# Reset cluster and start over
ansible-playbook -i inventory/mycluster/inventory.ini reset.yml -u <user> -b

# Then re-run deployment
ansible-playbook -i inventory/mycluster/inventory.ini cluster.yml -u <user> -b
```

### Useful Commands Reference

```bash
# Kubespray operations
ansible-playbook -i inventory/mycluster/inventory.ini cluster.yml -u <user> -b           # Deploy
ansible-playbook -i inventory/mycluster/inventory.ini reset.yml -u <user> -b             # Reset
ansible-playbook -i inventory/mycluster/inventory.ini scale.yml -u <user> -b             # Scale
ansible-playbook -i inventory/mycluster/inventory.ini upgrade-cluster.yml -u <user> -b   # Upgrade

# Kubernetes checks
kubectl get nodes
kubectl get pods -A
kubectl cluster-info
kubectl get cs  # Component status

# Calico checks
kubectl get ippools
kubectl get felixconfigurations
calicoctl node status

# Containerd checks
sudo crictl ps
sudo crictl images
sudo systemctl status containerd

# Log checking
sudo journalctl -u kubelet -f
sudo journalctl -u containerd -f
kubectl logs -n kube-system <pod-name>
```

---

## Additional Focus Areas

### 1. **Understanding Kubernetes Networking**

Key concepts to study:
- **Pod-to-Pod communication**: How pods communicate across nodes
- **Service networking**: ClusterIP, NodePort, LoadBalancer
- **Network policies**: Controlling traffic between pods
- **Ingress**: HTTP/HTTPS routing to services

### 2. **Calico Architecture**

Learn about:
- **Felix**: Agent on each node
- **BIRD**: BGP client (if using BGP)
- **Confd**: Configuration management
- **Typha**: Fan-out proxy for large clusters
- **IP Address Management (IPAM)**

### 3. **Containerd vs Docker**

Differences to understand:
- Containerd is lighter weight
- Uses crictl instead of docker CLI
- Better Kubernetes integration
- No docker-compose (use Kubernetes manifests)

### 4. **High Availability Considerations**

For production:
- 3+ control plane nodes (odd number)
- Separate etcd cluster (optional but recommended)
- Load balancer for API server
- Backup strategy for etcd

### 5. **Security Best Practices**

Important topics:
- **RBAC**: Role-based access control
- **Pod Security Policies/Standards**
- **Network Policies**: Restrict pod communication
- **Secrets Management**: Use external secret managers
- **Certificate Management**: Understanding PKI

---

## Next Steps After Setup

### 1. **Deploy Monitoring Stack**
```bash
# Prometheus + Grafana (using kube-prometheus-stack)
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack -n monitoring --create-namespace
```

### 2. **Setup Ingress Controller**
```bash
# Nginx Ingress Controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/baremetal/deploy.yaml
```

### 3. **Configure Storage**
- Local path provisioner
- NFS provisioner
- Rook/Ceph for distributed storage

### 4. **Backup Strategy**
- Velero for cluster backup
- Etcd snapshot backups
- GitOps for configuration backup

### 5. **CI/CD Integration**
- ArgoCD for GitOps
- Tekton for pipelines
- Harbor for container registry

---

## Quick Reference Checklist

### Pre-Deployment Checklist:
- [ ] VMs provisioned with correct specs
- [ ] Operating system installed and updated
- [ ] Static IPs configured or DHCP reservations set
- [ ] Swap disabled on all nodes
- [ ] Firewall configured or disabled
- [ ] SSH key-based authentication configured
- [ ] Sudo privileges configured for deployment user
- [ ] All nodes can ping each other
- [ ] Internet access available (or local mirror configured)
- [ ] DNS/hostnames configured
- [ ] Kubespray repository cloned
- [ ] Python dependencies installed
- [ ] Inventory file configured
- [ ] Variables files customized

### Post-Deployment Checklist:
- [ ] All nodes show "Ready" status
- [ ] All system pods running
- [ ] Calico pods running on all nodes
- [ ] CoreDNS pods running
- [ ] Etcd cluster healthy
- [ ] kubectl access configured
- [ ] Test deployment successful
- [ ] Network policies working (if enabled)
- [ ] Persistent storage configured (if needed)
- [ ] Monitoring deployed (if needed)
- [ ] Backup strategy in place

---

## Conclusion

This guide provides a comprehensive overview of deploying Kubernetes using Kubespray with Calico and containerd. The key to success is:

1. **Proper preparation**: Ensure all prerequisites are met
2. **Understand the components**: Know what Kubespray, Calico, and containerd do
3. **Configure carefully**: Review all configuration files before deployment
4. **Test thoroughly**: Validate each step and test after deployment
5. **Monitor and maintain**: Set up monitoring and backup strategies

Good luck with your Kubernetes deployment!
