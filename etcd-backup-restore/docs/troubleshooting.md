# etcd Backup and Restore Troubleshooting Guide

## Common Issues and Solutions

### Table of Contents
1. [Backup Issues](#backup-issues)
2. [Restore Issues](#restore-issues)
3. [Storage Issues](#storage-issues)
4. [Certificate Issues](#certificate-issues)
5. [Performance Issues](#performance-issues)
6. [Monitoring Issues](#monitoring-issues)

---

## Backup Issues

### Issue 1: Backup Job Fails with "Connection Refused"

**Symptoms:**
```
[ERROR] Failed to connect to etcd: connection refused
dial tcp 127.0.0.1:2379: connect: connection refused
```

**Possible Causes:**
- etcd is not running
- Wrong endpoint configured
- Network connectivity issues

**Solutions:**

1. Check if etcd is running:
```bash
kubectl get pods -n kube-system | grep etcd
# or on the node
systemctl status etcd
```

2. Verify etcd endpoints:
```bash
# Check etcd pod endpoint
kubectl describe pod etcd-master -n kube-system | grep -i listen

# Test connectivity
nc -zv 127.0.0.1 2379
```

3. Check etcd logs:
```bash
kubectl logs -n kube-system etcd-master
# or on the node
journalctl -u etcd -n 50
```

4. Verify the backup pod is running on a master node:
```bash
kubectl get pods -o wide | grep etcd-backup
```

**Fix:**
Update the Helm chart values with correct endpoint:
```yaml
etcd:
  endpoints: "https://CORRECT_IP:2379"
```

---

### Issue 2: Certificate Errors

**Symptoms:**
```
[ERROR] transport: authentication handshake failed: x509: certificate signed by unknown authority
```

**Solutions:**

1. Verify certificate paths:
```bash
ls -la /etc/kubernetes/pki/etcd/
# Should show: ca.crt, server.crt, server.key
```

2. Check certificate validity:
```bash
openssl x509 -in /etc/kubernetes/pki/etcd/server.crt -text -noout | grep -A2 Validity
```

3. Test etcdctl with certificates:
```bash
ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint health
```

4. Update Helm chart with correct certificate paths:
```yaml
etcd:
  certPath: "/etc/kubernetes/pki/etcd"
  caCert: "ca.crt"
  clientCert: "server.crt"
  clientKey: "server.key"
```

---

### Issue 3: "No Space Left on Device"

**Symptoms:**
```
[ERROR] Failed to save snapshot: no space left on device
```

**Solutions:**

1. Check disk space:
```bash
df -h /var/lib/etcd-backups
```

2. Clean up old backups:
```bash
./scripts/cleanup-old-backups.sh --retention-days 7
```

3. Increase PVC size (if using PVC storage):
```bash
kubectl edit pvc etcd-backup-storage -n kube-system
# Increase size field
```

4. Use cloud storage instead of local storage:
```yaml
storage:
  type: s3
  s3:
    enabled: true
    bucket: "my-etcd-backups"
```

---

### Issue 4: Backup Takes Too Long

**Symptoms:**
```
[WARN] Backup duration: 600 seconds (timeout reached)
Job exceeded timeout and was terminated
```

**Solutions:**

1. Increase timeout in Helm values:
```yaml
backup:
  timeout: 1200  # 20 minutes
```

2. Check etcd cluster size:
```bash
ETCDCTL_API=3 etcdctl endpoint status --write-out=table
# Look at DB SIZE column
```

3. Optimize etcd database:
```bash
# Defragment etcd (maintenance operation)
ETCDCTL_API=3 etcdctl defrag
ETCDCTL_API=3 etcdctl endpoint status --write-out=table
```

4. Run backup on a less busy time:
```yaml
backup:
  schedule: "0 2 * * *"  # 2 AM daily
```

5. Disable compression temporarily:
```yaml
backup:
  compression: false
```

---

### Issue 5: Backup Upload to S3 Fails

**Symptoms:**
```
[ERROR] Failed to upload to S3: access denied
upload failed: Unable to locate credentials
```

**Solutions:**

1. Check IAM role annotation on ServiceAccount:
```bash
kubectl describe sa etcd-backup -n kube-system
# Look for: eks.amazonaws.com/role-arn annotation
```

2. Verify IAM role has S3 permissions:
```bash
aws iam get-role-policy --role-name etcd-backup-role --policy-name S3Access
```

3. Test AWS credentials:
```bash
kubectl run -it --rm aws-test --image=amazon/aws-cli --restart=Never \
  --serviceaccount=etcd-backup -- s3 ls s3://my-etcd-backups/
```

4. Use access keys as fallback (not recommended for production):
```yaml
storage:
  s3:
    useIAMRole: false
    accessKeySecret:
      name: aws-credentials
      accessKeyField: access-key-id
      secretKeyField: secret-access-key
```

Create secret:
```bash
kubectl create secret generic aws-credentials \
  --from-literal=access-key-id=YOUR_KEY \
  --from-literal=secret-access-key=YOUR_SECRET \
  -n kube-system
```

---

## Restore Issues

### Issue 6: Restore Fails with "Snapshot Verification Failed"

**Symptoms:**
```
[ERROR] Snapshot verification failed!
Error: unexpected EOF
```

**Solutions:**

1. Check if snapshot file is complete:
```bash
ls -lh /path/to/snapshot.db
# Compare size with expected size
```

2. Verify snapshot integrity:
```bash
./scripts/verify-backup.sh --snapshot /path/to/snapshot.db
```

3. Re-download from cloud storage:
```bash
aws s3 cp s3://my-etcd-backups/path/to/snapshot.db /tmp/snapshot.db
```

4. Try with --skip-hash-check (last resort):
```bash
./scripts/restore-etcd.sh --snapshot /tmp/snapshot.db --skip-hash-check
```

---

### Issue 7: Cluster Won't Start After Restore

**Symptoms:**
```
etcd pod in CrashLoopBackOff
API server not responding
```

**Solutions:**

1. Check etcd logs:
```bash
kubectl logs -n kube-system etcd-master --previous
```

2. Verify data directory permissions:
```bash
ls -la /var/lib/etcd
chown -R etcd:etcd /var/lib/etcd
chmod -R 700 /var/lib/etcd
```

3. Check etcd manifest:
```bash
cat /etc/kubernetes/manifests/etcd.yaml
# Verify data-dir path matches restore location
```

4. Restore from pre-restore backup:
```bash
# Find pre-restore backup
ls -la /var/lib/etcd-backups/pre-restore-*

# Copy back
systemctl stop kubelet
rm -rf /var/lib/etcd
cp -a /var/lib/etcd-backups/pre-restore-TIMESTAMP /var/lib/etcd
systemctl start kubelet
```

5. Check for multi-node cluster issues:
```bash
# Verify initial-cluster configuration
grep initial-cluster /etc/kubernetes/manifests/etcd.yaml

# May need to update cluster configuration
etcdctl member list
```

---

### Issue 8: Data Missing After Restore

**Symptoms:**
```
Namespaces missing
Pods not found
ConfigMaps disappeared
```

**Solutions:**

1. Verify you restored the correct snapshot:
```bash
# Check snapshot metadata
cat /path/to/snapshot.db.metadata.json
```

2. Check snapshot timestamp:
```bash
ETCDCTL_API=3 etcdctl snapshot status /path/to/snapshot.db --write-out=json | jq
```

3. Verify all etcd keys were restored:
```bash
ETCDCTL_API=3 etcdctl get / --prefix --keys-only | wc -l
# Compare with expected count from metadata
```

4. Check specific resources:
```bash
kubectl get all --all-namespaces
kubectl get ns
kubectl get crd
```

5. Possible causes:
   - Wrong snapshot restored
   - Snapshot was from before resource creation
   - Multi-cluster environment (wrong cluster snapshot)

**Note:** etcd backups do NOT include:
- Persistent Volume data (need separate volume backups)
- Container images (stored in registries)
- Application logs

---

## Storage Issues

### Issue 9: S3 Bucket Access Denied

**Symptoms:**
```
[ERROR] An error occurred (403) when calling the PutObject operation: Forbidden
```

**Solutions:**

1. Verify bucket exists and you have access:
```bash
aws s3 ls s3://my-etcd-backups/
```

2. Check bucket policy:
```bash
aws s3api get-bucket-policy --bucket my-etcd-backups
```

3. Check IAM policy attached to role:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::my-etcd-backups",
        "arn:aws:s3:::my-etcd-backups/*"
      ]
    }
  ]
}
```

4. Verify trust relationship for IRSA:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/oidc.eks.REGION.amazonaws.com/id/OIDC_ID"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.REGION.amazonaws.com/id/OIDC_ID:sub": "system:serviceaccount:kube-system:etcd-backup"
        }
      }
    }
  ]
}
```

---

### Issue 10: GCS Authentication Failures

**Symptoms:**
```
[ERROR] Failed to authenticate to GCS
ServiceException: 401 Unauthorized
```

**Solutions:**

1. Verify Workload Identity is enabled:
```bash
gcloud container clusters describe CLUSTER_NAME --format="value(workloadIdentityConfig.workloadPool)"
```

2. Check service account binding:
```bash
kubectl describe sa etcd-backup -n kube-system
# Look for: iam.gke.io/gcp-service-account annotation
```

3. Verify GCP IAM binding:
```bash
gcloud iam service-accounts get-iam-policy \
  etcd-backup@PROJECT_ID.iam.gserviceaccount.com
```

4. Add IAM binding if missing:
```bash
gcloud iam service-accounts add-iam-policy-binding \
  etcd-backup@PROJECT_ID.iam.gserviceaccount.com \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:PROJECT_ID.svc.id.goog[kube-system/etcd-backup]"
```

---

## Certificate Issues

### Issue 11: Expired Certificates

**Symptoms:**
```
[ERROR] x509: certificate has expired or is not yet valid
```

**Solutions:**

1. Check certificate expiration:
```bash
for cert in /etc/kubernetes/pki/etcd/*.crt; do
  echo "Certificate: $cert"
  openssl x509 -in $cert -noout -enddate
  echo ""
done
```

2. Renew Kubernetes certificates:
```bash
# Backup current certificates
cp -r /etc/kubernetes/pki /etc/kubernetes/pki.backup

# Renew certificates (kubeadm)
kubeadm certs renew all

# Restart control plane components
systemctl restart kubelet
```

3. For manual etcd setup, regenerate certificates:
```bash
# Use your certificate generation tool
# Then restart etcd
systemctl restart etcd
```

---

## Performance Issues

### Issue 12: Slow Backup Performance

**Symptoms:**
```
Backup taking > 10 minutes for moderate-sized cluster
```

**Solutions:**

1. Check etcd performance:
```bash
ETCDCTL_API=3 etcdctl check perf
```

2. Check disk I/O:
```bash
iostat -x 1 10
# Look at %util column
```

3. Defragment etcd:
```bash
ETCDCTL_API=3 etcdctl defrag
```

4. Upgrade to faster storage (SSD/NVMe)

5. Reduce backup frequency for very large clusters:
```yaml
backup:
  schedule: "0 */12 * * *"  # Every 12 hours instead of 6
```

6. Use dedicated backup node with more resources:
```yaml
resources:
  limits:
    cpu: 1000m
    memory: 2Gi
  requests:
    cpu: 500m
    memory: 1Gi
```

---

## Monitoring Issues

### Issue 13: No Metrics in Prometheus

**Symptoms:**
```
Grafana dashboard shows no data
Prometheus not scraping backup metrics
```

**Solutions:**

1. Check ServiceMonitor:
```bash
kubectl get servicemonitor -n kube-system etcd-backup
```

2. Verify Prometheus is discovering the ServiceMonitor:
```bash
# Port forward to Prometheus
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090

# Check targets in browser: http://localhost:9090/targets
```

3. Check metric endpoint:
```bash
kubectl port-forward -n kube-system pod/etcd-backup-xxx 9090:9090
curl http://localhost:9090/metrics
```

4. Verify labels match Prometheus selector:
```bash
kubectl get servicemonitor etcd-backup -o yaml
# Check if labels match Prometheus serviceMonitorSelector
```

---

### Issue 14: Alerts Not Firing

**Symptoms:**
```
Backup failed but no alert received
```

**Solutions:**

1. Check AlertManager configuration:
```bash
kubectl get secret alertmanager-main -n monitoring -o yaml
```

2. Verify alert rules are loaded:
```bash
# In Prometheus UI: http://localhost:9090/alerts
```

3. Check AlertManager routing:
```bash
kubectl logs -n monitoring alertmanager-main-0
```

4. Test Slack webhook:
```bash
curl -X POST -H 'Content-type: application/json' \
  --data '{"text":"Test alert"}' \
  YOUR_SLACK_WEBHOOK_URL
```

5. Verify alert labels match routing rules:
```yaml
alerting:
  slack:
    enabled: true
    webhookUrl: "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
    channel: "#alerts"
```

---

## Emergency Procedures

### Emergency 1: Complete Cluster Failure

**Immediate Actions:**

1. **DON'T PANIC** - You have backups!

2. Assess the situation:
```bash
kubectl cluster-info
kubectl get nodes
kubectl get pods --all-namespaces
```

3. Check etcd health:
```bash
ETCDCTL_API=3 etcdctl endpoint health
ETCDCTL_API=3 etcdctl member list
```

4. If etcd is completely dead:
   - Download latest backup from cloud storage
   - Follow restore procedure in `restore-etcd.sh`
   - Verify cluster health after restore

5. If data corruption suspected:
   - Take snapshot of current state (for forensics)
   - Restore from last known good backup
   - Document what happened

---

### Emergency 2: Accidental Data Deletion

**Scenario:** Someone ran `kubectl delete ns production` 😱

**Actions:**

1. **STOP** - Don't make it worse
2. Don't run any more delete commands
3. Immediately take a snapshot of current state:
```bash
./scripts/backup-etcd.sh --cluster-name emergency-backup
```

4. Find backup from before deletion:
```bash
# List recent backups
aws s3 ls s3://my-etcd-backups/kubernetes/ --recursive | grep snapshot | tail -20
```

5. Restore from backup BEFORE the deletion:
```bash
./scripts/restore-etcd.sh --snapshot /path/to/backup-before-deletion.db
```

6. Verify restored data:
```bash
kubectl get ns production
kubectl get all -n production
```

---

## Debug Mode

### Enable Debug Logging

For backup script:
```bash
DEBUG=true ./scripts/backup-etcd.sh
```

For restore script:
```bash
DEBUG=true ./scripts/restore-etcd.sh --snapshot /path/to/snapshot.db --dry-run
```

For Helm chart:
```yaml
logLevel: "debug"
```

### Get Detailed etcd Info

```bash
# Cluster health
ETCDCTL_API=3 etcdctl endpoint health --write-out=table

# Member list
ETCDCTL_API=3 etcdctl member list --write-out=table

# Endpoint status
ETCDCTL_API=3 etcdctl endpoint status --write-out=table

# Check performance
ETCDCTL_API=3 etcdctl check perf

# List all keys
ETCDCTL_API=3 etcdctl get / --prefix --keys-only | head -20

# Get specific key
ETCDCTL_API=3 etcdctl get /registry/namespaces/default
```

---

## Getting Help

### Collect Diagnostic Information

Before asking for help, collect:

1. **Backup logs:**
```bash
kubectl logs -n kube-system cronjob/etcd-backup --tail=200 > backup-logs.txt
```

2. **etcd logs:**
```bash
kubectl logs -n kube-system etcd-master > etcd-logs.txt
```

3. **Cluster info:**
```bash
kubectl cluster-info dump > cluster-dump.txt
```

4. **Snapshot status:**
```bash
ETCDCTL_API=3 etcdctl snapshot status /path/to/snapshot.db > snapshot-status.txt
```

5. **Configuration:**
```bash
helm get values etcd-backup > values.yaml
```

### Support Channels

- GitHub Issues: [Repository URL]
- Slack: #etcd-backup channel
- Email: devops@yourcompany.com

---

## Prevention Best Practices

1. **Test Restores Regularly** - Monthly DR drills
2. **Monitor Backup Success** - Set up alerts
3. **Automate Everything** - Use Helm chart
4. **Document Changes** - Keep runbooks updated
5. **Version Control** - Store configs in Git
6. **Multi-Region Backups** - Don't put all eggs in one basket
7. **Validate Backups** - Run verification after each backup
8. **Capacity Planning** - Monitor storage growth
9. **Security Audits** - Regular access reviews
10. **Disaster Recovery Plan** - Document and test

---

**Last Updated:** February 3, 2026  
**Version:** 1.0.0
