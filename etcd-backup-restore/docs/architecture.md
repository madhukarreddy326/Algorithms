# etcd Backup and Restore Architecture

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                           │
│                                                                 │
│  ┌────────────┐      ┌────────────┐      ┌────────────┐      │
│  │   Master   │      │   Master   │      │   Master   │      │
│  │   Node 1   │      │   Node 2   │      │   Node 3   │      │
│  │            │      │            │      │            │      │
│  │  ┌──────┐  │      │  ┌──────┐  │      │  ┌──────┐  │      │
│  │  │ etcd │  │◄────►│  │ etcd │  │◄────►│  │ etcd │  │      │
│  │  └───┬──┘  │      │  └───┬──┘  │      │  └───┬──┘  │      │
│  └──────┼─────┘      └──────┼─────┘      └──────┼─────┘      │
│         │                   │                   │             │
│         └───────────────────┴───────────────────┘             │
│                             │                                 │
└─────────────────────────────┼─────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │  Backup CronJob │
                    │  (Runs on       │
                    │   Master Node)  │
                    └────────┬────────┘
                             │
                             │ 1. Take Snapshot
                             │ 2. Compress
                             │ 3. Encrypt (optional)
                             │ 4. Verify
                             │
                             ▼
                    ┌─────────────────┐
                    │  Local Storage  │
                    │  /var/lib/      │
                    │  etcd-backups/  │
                    └────────┬────────┘
                             │
                             │ Upload
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
        ▼                    ▼                    ▼
┌───────────────┐   ┌───────────────┐   ┌───────────────┐
│   AWS S3      │   │   GCS         │   │  Azure Blob   │
│               │   │               │   │               │
│ ┌───────────┐ │   │ ┌───────────┐ │   │ ┌───────────┐ │
│ │Versioned  │ │   │ │Versioned  │ │   │ │Versioned  │ │
│ │Encrypted  │ │   │ │Encrypted  │ │   │ │Encrypted  │ │
│ │Lifecycle  │ │   │ │Lifecycle  │ │   │ │Lifecycle  │ │
│ └───────────┘ │   │ └───────────┘ │   │ └───────────┘ │
└───────────────┘   └───────────────┘   └───────────────┘
        │                    │                    │
        └────────────────────┼────────────────────┘
                             │
                             │ Restore (when needed)
                             │
                             ▼
                    ┌─────────────────┐
                    │  Restore Job    │
                    │  1. Download    │
                    │  2. Verify      │
                    │  3. Decrypt     │
                    │  4. Decompress  │
                    │  5. Restore     │
                    └─────────────────┘
```

## Component Overview

### 1. etcd Cluster
- **Purpose**: Kubernetes' primary datastore
- **Data**: All cluster state, configurations, secrets, etc.
- **High Availability**: Typically 3 or 5 node cluster
- **Leader Election**: One leader, others are followers

### 2. Backup System

#### Backup CronJob
```yaml
Component: Kubernetes CronJob
Schedule: Every 6 hours (configurable)
Location: Runs on master nodes
Privileges: Requires access to etcd certificates
```

**Backup Process:**
1. **Health Check**: Verify etcd cluster health
2. **Snapshot**: Create point-in-time snapshot using etcdctl
3. **Compression**: Reduce size with gzip (optional)
4. **Encryption**: Encrypt with AES-256 (optional)
5. **Verification**: Verify snapshot integrity
6. **Metadata**: Create metadata file with backup info
7. **Upload**: Transfer to cloud storage
8. **Cleanup**: Remove old backups per retention policy

#### Local Storage
```
Path: /var/lib/etcd-backups/
Purpose: Temporary storage before cloud upload
Retention: 7 days (overwritten by newer backups)
```

#### Cloud Storage

**AWS S3:**
```
Storage Class: Standard-IA (Infrequent Access)
Encryption: Server-side AES-256
Versioning: Enabled
Lifecycle: Auto-delete after retention period
IAM: Role-based access (no credentials in pods)
```

**Google Cloud Storage:**
```
Storage Class: Nearline
Encryption: Customer-managed keys (optional)
Versioning: Enabled
Lifecycle: Auto-delete after retention period
Auth: Workload Identity
```

**Azure Blob Storage:**
```
Storage Tier: Cool
Encryption: Storage Service Encryption
Versioning: Enabled
Lifecycle: Auto-delete after retention period
Auth: Managed Identity
```

### 3. Monitoring and Alerting

```
┌─────────────────────────────────────────┐
│         Monitoring Stack                │
│                                         │
│  ┌──────────┐         ┌──────────┐    │
│  │Prometheus│◄────────│  Metrics  │    │
│  │          │         │  Exporter │    │
│  └────┬─────┘         └─────▲─────┘    │
│       │                     │          │
│       │                     │          │
│       ▼                     │          │
│  ┌──────────┐         Backup CronJob   │
│  │ Grafana  │               │          │
│  │Dashboard │               │          │
│  └──────────┘               │          │
│       │                     │          │
│       ▼                     ▼          │
│  ┌──────────┐         ┌──────────┐    │
│  │AlertMan- │────────►│  Slack/  │    │
│  │ager      │         │PagerDuty │    │
│  └──────────┘         └──────────┘    │
└─────────────────────────────────────────┘
```

**Monitored Metrics:**
- Backup success/failure rate
- Backup duration
- Snapshot file size
- Time since last successful backup
- Storage utilization
- etcd cluster health

**Alert Rules:**
```yaml
Critical:
  - No successful backup in 12 hours
  - Backup job failed 3 consecutive times
  - Unable to upload to cloud storage
  - Snapshot verification failed

Warning:
  - Backup duration > 5 minutes
  - Snapshot size increased > 50%
  - Storage usage > 80%
  - etcd cluster unhealthy
```

### 4. Restore System

#### Restore Process

```
Step 1: Pre-Restore
├── Download snapshot from cloud storage
├── Verify snapshot integrity
├── Decrypt snapshot (if encrypted)
├── Decompress snapshot (if compressed)
├── Backup current etcd data
└── User confirmation

Step 2: Cluster Preparation
├── Stop Kubernetes API server
├── Stop etcd service (if needed)
└── Verify cluster is quiescent

Step 3: Data Restore
├── Run etcdctl snapshot restore
├── Move restored data to etcd data dir
├── Set correct permissions
└── Update etcd configuration (if needed)

Step 4: Cluster Restart
├── Start etcd service
├── Start Kubernetes API server
├── Wait for cluster convergence
└── Verify cluster health

Step 5: Verification
├── Check node status
├── Check pod status
├── Verify namespaces
├── Check critical resources
└── Monitor for errors
```

## Data Flow

### Backup Data Flow

```
1. etcd Data (in-memory + disk)
   ↓
2. etcdctl snapshot save
   ↓
3. Snapshot file (.db) [~100-500 MB]
   ↓
4. Compression (gzip)
   ↓
5. Compressed file (.db.gz) [~30-150 MB, 70% reduction]
   ↓
6. Encryption (optional)
   ↓
7. Encrypted file (.db.gz.enc)
   ↓
8. Upload to Cloud Storage
   ↓
9. Cloud Storage (S3/GCS/Azure)
   - Versioning enabled
   - Encryption at rest
   - Lifecycle policies
   - Multi-region replication (optional)
```

### Restore Data Flow

```
1. Download from Cloud Storage
   ↓
2. Encrypted file (.db.gz.enc)
   ↓
3. Decryption
   ↓
4. Compressed file (.db.gz)
   ↓
5. Decompression
   ↓
6. Snapshot file (.db)
   ↓
7. etcdctl snapshot restore
   ↓
8. New etcd data directory
   ↓
9. Replace old etcd data
   ↓
10. Restart etcd
   ↓
11. Kubernetes cluster operational
```

## Security Architecture

### Access Control

```
┌─────────────────────────────────────────┐
│         Kubernetes RBAC                 │
│                                         │
│  ServiceAccount: etcd-backup            │
│  Permissions:                           │
│    - Read etcd certificates             │
│    - Access etcd endpoints              │
│    - Create backup pods                 │
│    - Read/Write to storage secrets      │
└─────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────┐
│       etcd TLS Certificates             │
│                                         │
│  - CA Certificate (ca.crt)              │
│  - Client Certificate (client.crt)      │
│  - Client Key (client.key)              │
│                                         │
│  Mounted as: Kubernetes Secrets or      │
│  HostPath from /etc/kubernetes/pki/etcd │
└─────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────┐
│       Cloud Storage Access              │
│                                         │
│  AWS: IAM Role for Service Account      │
│  GCP: Workload Identity                 │
│  Azure: Managed Identity                │
│                                         │
│  Principle: No long-lived credentials   │
└─────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────┐
│       Encryption at Rest                │
│                                         │
│  - Backup file encryption (optional)    │
│  - Cloud storage encryption (always)    │
│  - etcd data encryption (recommended)   │
└─────────────────────────────────────────┘
```

### Security Best Practices

1. **Least Privilege**: Backup pods only have necessary permissions
2. **Certificate-based Auth**: All etcd access uses TLS certificates
3. **No Long-lived Credentials**: Use IAM roles/Workload Identity
4. **Encryption in Transit**: All network communication encrypted
5. **Encryption at Rest**: Backups and storage encrypted
6. **Audit Logging**: All access to backups logged
7. **Network Policies**: Restrict backup pod network access
8. **Secret Management**: Store credentials in Kubernetes Secrets
9. **Regular Rotation**: Rotate credentials and certificates
10. **Access Reviews**: Regular review of who can access backups

## Disaster Recovery Architecture

### RTO/RPO Targets

```
┌──────────────────┬─────────┬─────────┬──────────┐
│  Environment     │   RTO   │   RPO   │ Recovery │
├──────────────────┼─────────┼─────────┼──────────┤
│  Production      │ 15 min  │ 6 hours │  Multi-  │
│  (Critical)      │         │         │  Region  │
├──────────────────┼─────────┼─────────┼──────────┤
│  Production      │ 30 min  │ 6 hours │  Single  │
│  (Standard)      │         │         │  Region  │
├──────────────────┼─────────┼─────────┼──────────┤
│  Staging         │ 1 hour  │ 12 hrs  │  Single  │
│                  │         │         │  Region  │
├──────────────────┼─────────┼─────────┼──────────┤
│  Development     │ 4 hours │ 24 hrs  │  Best    │
│                  │         │         │  Effort  │
└──────────────────┴─────────┴─────────┴──────────┘
```

### DR Scenarios

#### Scenario 1: Single etcd Node Failure
```
Impact: Minimal (if cluster has 3+ nodes)
Recovery: Automatic (etcd cluster replication)
Action: None (cluster self-heals)
```

#### Scenario 2: etcd Data Corruption
```
Impact: Medium (cluster may be unstable)
Recovery: Restore from latest backup
RTO: 15-30 minutes
Steps: Run restore script on affected node
```

#### Scenario 3: Complete Cluster Loss
```
Impact: High (full cluster outage)
Recovery: Rebuild cluster + restore from backup
RTO: 30-60 minutes
Steps:
  1. Provision new cluster infrastructure
  2. Install Kubernetes
  3. Restore etcd from backup
  4. Verify cluster health
  5. Restore applications
```

#### Scenario 4: Region Outage
```
Impact: Critical (if single region)
Recovery: Failover to secondary region + restore
RTO: Depends on multi-region setup
Steps:
  1. Activate secondary region cluster
  2. Download backup from alternate location
  3. Restore etcd data
  4. Update DNS/load balancers
  5. Verify applications
```

## High Availability Setup

### Multi-Region Backup Strategy

```
Primary Region (us-east-1)
├── etcd Cluster (3 nodes)
├── Backup CronJob
└── S3 Bucket (with versioning)
     │
     ├── Cross-Region Replication
     │   ├── us-west-2 (secondary)
     │   └── eu-west-1 (tertiary)
     │
     └── Backup Lifecycle
         ├── Standard: 0-7 days
         ├── Standard-IA: 7-30 days
         └── Glacier: 30-90 days
```

### Backup Verification Strategy

```
Continuous Verification:
├── Immediate: Snapshot status check (every backup)
├── Daily: Test restore on dedicated cluster
├── Weekly: Full DR drill in staging
└── Monthly: Full DR drill in production-like environment

Automated Testing:
├── CI/CD Pipeline
├── Dedicated test cluster
├── Automated verification scripts
└── Alert on any failures
```

## Scaling Considerations

### Large Clusters (> 1000 nodes)

```
Challenge: Larger etcd databases (> 1 GB)

Solutions:
├── Increase backup timeout
├── More frequent backups (every 2-4 hours)
├── Dedicated backup node (larger instance)
├── Faster storage (SSD/NVMe)
├── Parallel compression
└── Incremental backups (if supported)
```

### Multi-Cluster Environments

```
Setup:
├── Production Clusters: 5
├── Staging Clusters: 3
├── Dev Clusters: 10

Strategy:
├── Centralized backup storage
├── Per-cluster backup schedules
├── Consolidated monitoring
├── Shared alerting
└── Unified retention policies

Directory Structure:
s3://backups/
├── prod/
│   ├── cluster-1/
│   ├── cluster-2/
│   └── ...
├── staging/
│   └── ...
└── dev/
    └── ...
```

## Cost Optimization

### Storage Cost Analysis

```
Example: Production Cluster
├── Snapshot size: 300 MB (uncompressed)
├── Compressed: 90 MB (70% reduction)
├── Frequency: Every 6 hours (4 backups/day)
├── Retention: 30 days
├── Total backups: 120 (4 × 30)
├── Total storage: 10.8 GB (120 × 90 MB)

Monthly Cost (AWS S3 Standard-IA):
├── Storage: 10.8 GB × $0.0125/GB = $0.14
├── PUT requests: 120 × $0.01/1000 = $0.001
├── GET requests (restore): ~$0.001
├── Total: ~$0.15/month

Annual cost: ~$1.80 per cluster
```

### Optimization Strategies

1. **Compression**: Save 70% storage (enabled by default)
2. **Lifecycle Policies**: Auto-transition to cheaper tiers
3. **Intelligent Tiering**: Let cloud provider optimize
4. **Retention Tuning**: Keep only necessary backups
5. **Deduplication**: For multiple clusters (if supported)
6. **Regional Selection**: Cheaper regions for long-term storage

---

## Summary

This architecture provides:
- ✅ **Reliability**: Multi-layer backup strategy
- ✅ **Security**: End-to-end encryption and access control
- ✅ **Scalability**: Handles clusters of any size
- ✅ **Automation**: Fully automated backup and verification
- ✅ **Monitoring**: Comprehensive metrics and alerting
- ✅ **Cost-effective**: Optimized storage and lifecycle
- ✅ **Compliance**: Meets regulatory requirements
- ✅ **Disaster Recovery**: Tested and documented procedures

---

**Next Steps**: See `../README.md` for implementation guide
