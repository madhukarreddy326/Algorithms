# etcd Backup and Restore - Quick Start Guide

Get up and running with etcd backups in 5 minutes!

## Prerequisites

- Kubernetes cluster (1.19+)
- Helm 3.x installed
- kubectl configured
- Access to master nodes (for on-premise clusters)
- Cloud storage account (AWS S3, GCS, or Azure Blob)

## Quick Installation

### Option 1: Using Helm Chart (Recommended)

```bash
# 1. Clone or navigate to the repository
cd etcd-backup-restore

# 2. Install with default settings (local storage)
helm install etcd-backup ./helm-chart/etcd-backup \
  --namespace kube-system \
  --create-namespace

# 3. Verify installation
kubectl get cronjob -n kube-system etcd-backup
kubectl get pods -n kube-system -l app.kubernetes.io/name=etcd-backup
```

### Option 2: With AWS S3 Storage

```bash
# 1. Set up S3 bucket (using Terraform)
cd examples/terraform
terraform init
terraform apply \
  -var="bucket_name=my-etcd-backups" \
  -var="eks_cluster_name=my-cluster" \
  -var="environment=production"

# 2. Install Helm chart with S3 configuration
cd ../../
helm install etcd-backup ./helm-chart/etcd-backup \
  --namespace kube-system \
  --set storage.type=s3 \
  --set storage.s3.enabled=true \
  --set storage.s3.bucket=my-etcd-backups \
  --set storage.s3.region=us-east-1 \
  --set storage.s3.useIAMRole=true \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="arn:aws:iam::ACCOUNT_ID:role/etcd-backup-role"
```

### Option 3: Manual Script Execution

```bash
# For immediate one-time backup
cd scripts

# Make scripts executable
chmod +x *.sh

# Run backup
sudo ./backup-etcd.sh \
  --cluster-name my-cluster \
  --backup-dir /var/lib/etcd-backups
```

## Verify Backup

```bash
# Check if backup job ran successfully
kubectl logs -n kube-system job/etcd-backup-<timestamp>

# Verify backup file
ls -lh /var/lib/etcd-backups/
# or for S3
aws s3 ls s3://my-etcd-backups/kubernetes/

# Verify snapshot integrity
./scripts/verify-backup.sh --snapshot /path/to/snapshot.db
```

## Test Backup

```bash
# Run the automated test suite
cd examples
chmod +x test-backup-restore.sh
./test-backup-restore.sh
```

## Trigger Manual Backup

```bash
# Create a manual backup job
kubectl create job --from=cronjob/etcd-backup etcd-backup-manual -n kube-system

# Watch the job
kubectl get jobs -n kube-system -w

# View logs
kubectl logs -n kube-system job/etcd-backup-manual
```

## Configuration

### Customize Backup Schedule

```bash
# Edit values and upgrade
helm upgrade etcd-backup ./helm-chart/etcd-backup \
  --namespace kube-system \
  --set backup.schedule="0 */4 * * *"  # Every 4 hours
```

### Change Retention Period

```bash
helm upgrade etcd-backup ./helm-chart/etcd-backup \
  --namespace kube-system \
  --set backup.retentionDays=60  # Keep for 60 days
```

### Enable Encryption

```bash
# Create encryption secret
kubectl create secret generic etcd-backup-encryption \
  --from-literal=encryption-key="your-secret-key" \
  -n kube-system

# Upgrade with encryption enabled
helm upgrade etcd-backup ./helm-chart/etcd-backup \
  --namespace kube-system \
  --set backup.encryption.enabled=true
```

## Restore from Backup

### ⚠️ WARNING: Read Before Proceeding

Restoring etcd will:
- **Overwrite all cluster data**
- **Cause cluster downtime** (5-30 minutes)
- **Lose all data created after the backup**

**Always test in a non-production environment first!**

### Restore Procedure

```bash
# 1. Download backup (if from cloud storage)
aws s3 cp s3://my-etcd-backups/kubernetes/snapshot.db /tmp/snapshot.db

# 2. Run restore script (with confirmation)
cd scripts
sudo ./restore-etcd.sh \
  --snapshot /tmp/snapshot.db \
  --confirm

# 3. Verify cluster health
kubectl get nodes
kubectl get pods --all-namespaces
```

### Dry Run (Recommended First)

```bash
# See what would be done without actually restoring
./scripts/restore-etcd.sh \
  --snapshot /tmp/snapshot.db \
  --dry-run
```

## Monitoring

### View Backup Status

```bash
# Check CronJob status
kubectl get cronjob -n kube-system etcd-backup

# View recent jobs
kubectl get jobs -n kube-system -l app.kubernetes.io/name=etcd-backup

# Check logs
kubectl logs -n kube-system -l app.kubernetes.io/name=etcd-backup --tail=100
```

### Set Up Alerts

```bash
# Install with Slack notifications
helm upgrade etcd-backup ./helm-chart/etcd-backup \
  --namespace kube-system \
  --set alerting.enabled=true \
  --set alerting.slack.enabled=true \
  --set alerting.slack.webhookUrl="https://hooks.slack.com/services/YOUR/WEBHOOK/URL" \
  --set alerting.slack.channel="#alerts"
```

## Common Commands

### List All Backups

```bash
# Local storage
ls -lh /var/lib/etcd-backups/

# S3
aws s3 ls s3://my-etcd-backups/kubernetes/ --recursive

# GCS
gsutil ls -l gs://my-etcd-backups/kubernetes/
```

### Cleanup Old Backups

```bash
cd scripts
./cleanup-old-backups.sh --retention-days 30
```

### Check etcd Health

```bash
ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint health
```

## Troubleshooting

### Backup Job Failing?

```bash
# Check pod logs
kubectl logs -n kube-system -l app.kubernetes.io/name=etcd-backup

# Check pod status
kubectl describe pod -n kube-system -l app.kubernetes.io/name=etcd-backup

# Check node selector (must run on master)
kubectl get pods -n kube-system -l app.kubernetes.io/name=etcd-backup -o wide
```

### Can't Access etcd?

```bash
# Verify certificates exist
ls -la /etc/kubernetes/pki/etcd/

# Test etcd connectivity
kubectl exec -it -n kube-system etcd-master -- sh -c \
  "ETCDCTL_API=3 etcdctl endpoint health"
```

### Storage Issues?

```bash
# Check disk space
df -h /var/lib/etcd-backups

# Check S3 permissions
aws s3 ls s3://my-etcd-backups/

# Check IAM role
kubectl describe sa etcd-backup -n kube-system
```

## Next Steps

1. **Read the full documentation**: [README.md](README.md)
2. **Set up monitoring**: Configure Prometheus/Grafana dashboards
3. **Test restore procedure**: In a test cluster
4. **Schedule DR drills**: Monthly restore tests
5. **Review architecture**: [docs/architecture.md](docs/architecture.md)
6. **Configure alerts**: Set up Slack/PagerDuty notifications
7. **Multi-region setup**: For disaster recovery

## Backup Frequency Recommendations

| Environment | Frequency | Retention |
|-------------|-----------|-----------|
| Production Critical | Every 2-4 hours | 60 days |
| Production Standard | Every 6 hours | 30 days |
| Staging | Every 12 hours | 14 days |
| Development | Daily | 7 days |

## Support

- **Documentation**: [docs/](docs/)
- **Troubleshooting**: [docs/troubleshooting.md](docs/troubleshooting.md)
- **Architecture**: [docs/architecture.md](docs/architecture.md)
- **Issues**: GitHub Issues
- **Slack**: #etcd-backup channel

## Important Notes

✅ **DO:**
- Test restore procedures regularly
- Monitor backup success/failure
- Keep backups in multiple locations
- Document your restore procedure
- Run backups during low-traffic periods
- Encrypt sensitive backups

❌ **DON'T:**
- Restore production without testing
- Skip backup verification
- Store only local backups
- Ignore backup failures
- Use expired certificates
- Share backup credentials

---

**Need help?** See [docs/troubleshooting.md](docs/troubleshooting.md) or open an issue!
