# etcd Backup and Restore Strategy for Kubernetes

## Overview

This repository provides a comprehensive DevOps strategy for backing up and restoring etcd in Kubernetes clusters. etcd is the distributed key-value store that serves as Kubernetes' backing store for all cluster data.

## Table of Contents

1. [What is etcd and Why Backup?](#what-is-etcd-and-why-backup)
2. [What's Included in an etcd Backup?](#whats-included-in-an-etcd-backup)
3. [Backup Frequency Standards](#backup-frequency-standards)
4. [Helm Chart Implementation](#helm-chart-implementation)
5. [Backup Commands](#backup-commands)
6. [Restore Commands](#restore-commands)
7. [Storage Strategy](#storage-strategy)
8. [DevOps Best Practices](#devops-best-practices)
9. [Testing Strategy](#testing-strategy)

---

## What is etcd and Why Backup?

etcd stores:
- All Kubernetes objects (Pods, Services, Deployments, ConfigMaps, Secrets, etc.)
- Cluster state and configuration
- API server data
- Resource metadata and specifications

**Without etcd backups, you risk losing your entire cluster configuration in case of:**
- Hardware failures
- Data corruption
- Accidental deletions
- Disaster scenarios

---

## What's Included in an etcd Backup?

An etcd backup snapshot includes:

```
✓ All Kubernetes objects and resources
✓ Cluster roles and bindings (RBAC)
✓ Service accounts
✓ Persistent Volume Claims (metadata, not data)
✓ ConfigMaps and Secrets
✓ Namespaces
✓ Custom Resource Definitions (CRDs)
✓ Network policies
✓ Ingress configurations
```

**NOT included:**
- Actual Persistent Volume data (requires separate volume backups)
- Container images (stored in registries)
- Application logs
- Metrics history

---

## Backup Frequency Standards

### Industry Standard Recommendations:

| Environment | Backup Frequency | Retention Period |
|-------------|------------------|------------------|
| **Production** | Every 4-6 hours | 30 days |
| **Staging** | Every 12 hours | 14 days |
| **Development** | Daily | 7 days |
| **Critical Production** | Every 1-2 hours | 60-90 days |

### Recommended Schedule:
```yaml
Production Cluster:
  - Full backup: Every 6 hours
  - Incremental: Every 30 minutes (if supported)
  - Pre-change snapshot: Before any major change
  - Retention: 30 days rolling

Staging/Dev:
  - Full backup: Daily (2 AM)
  - Retention: 7-14 days
```

---

## Helm Chart Implementation

### Yes, there are Helm standards for etcd backup!

We provide a production-ready Helm chart that implements:
- Automated CronJob-based backups
- Multiple storage backends (S3, GCS, Azure Blob, NFS)
- Monitoring and alerting integration
- Encryption at rest
- Backup verification

**See:** `helm-chart/etcd-backup/` directory for full implementation

### Quick Start:
```bash
# Install the etcd backup Helm chart
helm install etcd-backup ./helm-chart/etcd-backup \
  --namespace kube-system \
  --set backup.schedule="0 */6 * * *" \
  --set storage.s3.enabled=true \
  --set storage.s3.bucket=my-etcd-backups
```

---

## Backup Commands

### Method 1: Using etcdctl (Recommended)

```bash
# Set etcd version
ETCDCTL_API=3

# Take a snapshot
etcdctl snapshot save /backup/etcd-snapshot-$(date +%Y%m%d-%H%M%S).db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# Verify the snapshot
etcdctl snapshot status /backup/etcd-snapshot-$(date +%Y%m%d-%H%M%S).db \
  --write-out=table
```

### Method 2: Using Kubernetes Native Tools

```bash
# For managed Kubernetes (EKS, GKE, AKS)
# Access etcd pod
kubectl exec -n kube-system etcd-master -it -- sh

# Inside the pod
ETCDCTL_API=3 etcdctl snapshot save /tmp/snapshot.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# Copy snapshot out
kubectl cp kube-system/etcd-master:/tmp/snapshot.db ./snapshot.db
```

### Method 3: Automated Script (Our Implementation)

```bash
# Use our provided script
./scripts/backup-etcd.sh --storage s3://my-bucket/etcd-backups
```

**See:** `scripts/backup-etcd.sh` for full implementation

---

## Restore Commands

### ⚠️ CRITICAL: Restore Process

**IMPORTANT:** Restoring etcd will overwrite your current cluster state. Always:
1. Take a current backup before restoring
2. Test restore procedures in a non-production environment
3. Plan for cluster downtime (5-30 minutes)

### Restore Procedure:

#### Step 1: Stop API Server
```bash
# On master node
sudo mv /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/
```

#### Step 2: Restore etcd Snapshot
```bash
ETCDCTL_API=3 etcdctl snapshot restore /backup/snapshot.db \
  --name=master \
  --initial-cluster=master=https://MASTER_IP:2380 \
  --initial-cluster-token=etcd-cluster-1 \
  --initial-advertise-peer-urls=https://MASTER_IP:2380 \
  --data-dir=/var/lib/etcd-restore

# Move restored data
sudo rm -rf /var/lib/etcd
sudo mv /var/lib/etcd-restore /var/lib/etcd
```

#### Step 3: Update etcd Manifest
```bash
# Update data-dir in etcd manifest if needed
sudo vi /etc/kubernetes/manifests/etcd.yaml
```

#### Step 4: Start Services
```bash
# Restore API server
sudo mv /tmp/kube-apiserver.yaml /etc/kubernetes/manifests/

# Wait for cluster to come up
kubectl get nodes
kubectl get pods --all-namespaces
```

### Automated Restore Script:
```bash
# Use our provided script with safety checks
./scripts/restore-etcd.sh --snapshot /backup/snapshot.db --confirm
```

**See:** `scripts/restore-etcd.sh` for full implementation

---

## Storage Strategy

### Where to Store etcd Backups?

#### Best Practices for Storage:

1. **Multi-Location Strategy (Recommended):**
   ```
   Primary:   S3/GCS/Azure Blob (versioned bucket)
   Secondary: Different cloud region
   Tertiary:  On-premises NAS/NFS (air-gapped)
   ```

2. **Storage Requirements:**
   - **Durability:** 99.999999999% (11 nines)
   - **Encryption:** At rest and in transit
   - **Versioning:** Enabled
   - **Lifecycle policies:** Auto-delete old backups
   - **Access control:** Strict IAM policies

#### Storage Options by Provider:

| Provider | Storage Service | Typical Size | Cost (per GB/month) |
|----------|----------------|--------------|---------------------|
| AWS | S3 (Standard) | 100-500 MB | $0.023 |
| AWS | S3 (Glacier) | 100-500 MB | $0.004 |
| GCP | Cloud Storage | 100-500 MB | $0.020 |
| Azure | Blob Storage | 100-500 MB | $0.018 |
| Self-hosted | NFS/Ceph | 100-500 MB | Variable |

#### Directory Structure:
```
s3://my-etcd-backups/
├── production/
│   ├── cluster-1/
│   │   ├── 2026/
│   │   │   ├── 02/
│   │   │   │   ├── 03/
│   │   │   │   │   ├── etcd-snapshot-20260203-020000.db
│   │   │   │   │   ├── etcd-snapshot-20260203-080000.db
│   │   │   │   │   └── etcd-snapshot-20260203-140000.db
├── staging/
└── dev/
```

---

## DevOps Best Practices

### 1. Automation Strategy

```yaml
Production Workflow:
  1. CronJob runs backup every 6 hours
  2. Upload to S3 with encryption
  3. Verify snapshot integrity
  4. Send metrics to monitoring system
  5. Alert on failure
  6. Cleanup old backups (30 days retention)
```

### 2. Monitoring and Alerting

**Key Metrics to Track:**
- Backup success/failure rate
- Backup file size trends
- Backup duration
- Time since last successful backup
- Storage utilization

**Alert Conditions:**
```yaml
Critical:
  - Backup failed for > 12 hours
  - Unable to upload to storage
  - Snapshot verification failed

Warning:
  - Backup duration > 5 minutes
  - Backup size increased > 50%
  - Storage nearly full (> 80%)
```

### 3. CI/CD Integration

```yaml
Pre-Deployment:
  - Take snapshot before applying changes
  - Tag with deployment ID
  - Verify backup succeeded

Post-Deployment:
  - Keep pre-deployment backup for 7 days
  - Monitor cluster health
  - Keep rollback snapshot ready
```

### 4. Disaster Recovery Plan

```yaml
RTO (Recovery Time Objective): 15 minutes
RPO (Recovery Point Objective): 6 hours

DR Runbook:
  1. Identify failure (< 2 min)
  2. Access backup storage (< 1 min)
  3. Download snapshot (< 2 min)
  4. Execute restore script (< 5 min)
  5. Verify cluster health (< 5 min)
```

### 5. Security Best Practices

```yaml
✓ Encrypt backups at rest (AES-256)
✓ Encrypt in transit (TLS 1.3)
✓ Use IAM roles (no long-lived credentials)
✓ Enable audit logging for backup access
✓ Implement backup retention policies
✓ Regular restore testing (monthly)
✓ Restrict etcd access with certificates
✓ Use separate service accounts for backup jobs
```

### 6. Infrastructure as Code

```yaml
✓ Store all backup configurations in Git
✓ Use Helm charts for deployment
✓ Version control restore procedures
✓ Document runbooks in Markdown
✓ Automate testing with CI/CD
```

---

## Testing Strategy

### How to Test etcd Backup and Restore (DevOps Mode)

#### Test Environment Setup

1. **Use a Separate Test Cluster:**
   ```bash
   # Create a test cluster (kind, minikube, or small cloud cluster)
   kind create cluster --name etcd-test
   ```

2. **Populate with Test Data:**
   ```bash
   # Create test resources
   kubectl create namespace test-backup
   kubectl create configmap test-config --from-literal=key=value -n test-backup
   kubectl create secret generic test-secret --from-literal=password=test123 -n test-backup
   kubectl run test-pod --image=nginx -n test-backup
   ```

3. **Take Backup:**
   ```bash
   ./scripts/backup-etcd.sh --test-mode
   ```

4. **Verify Backup:**
   ```bash
   ./scripts/verify-backup.sh --snapshot /path/to/snapshot.db
   ```

5. **Delete Test Data:**
   ```bash
   kubectl delete namespace test-backup
   ```

6. **Restore Backup:**
   ```bash
   ./scripts/restore-etcd.sh --snapshot /path/to/snapshot.db
   ```

7. **Verify Restoration:**
   ```bash
   kubectl get all -n test-backup
   kubectl get configmap test-config -n test-backup -o yaml
   kubectl get secret test-secret -n test-backup
   ```

#### Automated Testing Pipeline

**See:** `examples/test-pipeline.yaml` for full CI/CD integration

```yaml
# Test schedule: Weekly (Saturday 2 AM)
apiVersion: batch/v1
kind: CronJob
metadata:
  name: etcd-backup-restore-test
spec:
  schedule: "0 2 * * 6"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: test-runner
            image: etcd-backup-tester:latest
            command: ["/scripts/test-backup-restore.sh"]
```

#### Test Checklist

```markdown
✓ Backup completes successfully
✓ Backup file size is reasonable (100-500 MB typical)
✓ Snapshot can be verified with etcdctl
✓ Backup uploads to storage successfully
✓ Restore completes without errors
✓ All namespaces are restored
✓ ConfigMaps and Secrets are intact
✓ RBAC policies are preserved
✓ CRDs are restored correctly
✓ Cluster is fully functional post-restore
✓ Backup/restore duration is within SLA
✓ No data loss detected
```

### Testing Frequency

| Test Type | Frequency | Environment |
|-----------|-----------|-------------|
| **Backup verification** | Daily | All environments |
| **Restore test (non-prod)** | Weekly | Staging |
| **Full DR drill** | Monthly | Dedicated test cluster |
| **Cross-region restore** | Quarterly | Production (planned) |

---

## Quick Reference

### Common Commands

```bash
# Take backup
ETCDCTL_API=3 etcdctl snapshot save /backup/snapshot.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# Verify backup
ETCDCTL_API=3 etcdctl snapshot status /backup/snapshot.db

# Restore backup (DESTRUCTIVE)
ETCDCTL_API=3 etcdctl snapshot restore /backup/snapshot.db \
  --data-dir=/var/lib/etcd-restore

# List all keys in etcd
ETCDCTL_API=3 etcdctl get / --prefix --keys-only

# Check etcd health
ETCDCTL_API=3 etcdctl endpoint health

# Check etcd member list
ETCDCTL_API=3 etcdctl member list
```

---

## Directory Structure

```
etcd-backup-restore/
├── README.md                          # This file
├── helm-chart/
│   └── etcd-backup/
│       ├── Chart.yaml                 # Helm chart metadata
│       ├── values.yaml                # Configuration values
│       └── templates/
│           ├── cronjob.yaml           # Backup CronJob
│           ├── configmap.yaml         # Scripts and config
│           ├── secret.yaml            # Credentials
│           ├── serviceaccount.yaml    # RBAC
│           └── monitoring.yaml        # Alerts and dashboards
├── scripts/
│   ├── backup-etcd.sh                 # Backup script
│   ├── restore-etcd.sh                # Restore script
│   ├── verify-backup.sh               # Verification script
│   └── cleanup-old-backups.sh         # Retention script
├── docs/
│   ├── architecture.md                # Architecture diagram
│   ├── troubleshooting.md             # Common issues
│   └── runbooks/
│       ├── backup-failure.md          # Runbook for backup failures
│       └── restore-procedure.md       # Step-by-step restore guide
└── examples/
    ├── test-pipeline.yaml             # CI/CD test pipeline
    ├── terraform/                     # Infrastructure as Code
    │   ├── s3-bucket.tf               # S3 bucket setup
    │   └── iam-roles.tf               # IAM policies
    └── kubernetes/
        ├── backup-job.yaml            # Manual backup job
        └── restore-pod.yaml           # Restore helper pod
```

---

## Getting Started

### 1. Install Helm Chart
```bash
cd helm-chart
helm install etcd-backup ./etcd-backup -n kube-system
```

### 2. Configure Storage
```bash
helm upgrade etcd-backup ./etcd-backup \
  --set storage.s3.enabled=true \
  --set storage.s3.bucket=my-backups \
  --set storage.s3.region=us-west-2
```

### 3. Test Backup
```bash
kubectl create job --from=cronjob/etcd-backup test-backup -n kube-system
kubectl logs -f job/test-backup -n kube-system
```

### 4. Verify
```bash
# Check backup in storage
aws s3 ls s3://my-backups/etcd/

# Verify snapshot
./scripts/verify-backup.sh --snapshot s3://my-backups/etcd/snapshot.db
```

---

## Support and Contributing

For issues, questions, or contributions, please refer to:
- `docs/troubleshooting.md` - Common issues and solutions
- `docs/runbooks/` - Operational procedures
- GitHub Issues - Report bugs or request features

---

## License

MIT License - See LICENSE file for details

---

## Additional Resources

- [etcd Official Documentation](https://etcd.io/docs/)
- [Kubernetes Backup Best Practices](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/#backing-up-an-etcd-cluster)
- [CNCF Disaster Recovery Guidelines](https://www.cncf.io/)
- [Velero - Alternative Backup Solution](https://velero.io/)

---

**Last Updated:** February 3, 2026  
**Version:** 1.0.0
