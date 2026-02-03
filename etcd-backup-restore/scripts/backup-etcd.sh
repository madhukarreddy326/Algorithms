#!/bin/bash
################################################################################
# etcd Backup Script
# Description: Production-grade etcd backup script with multiple storage options
# Author: DevOps Team
# Version: 1.0.0
################################################################################

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
ETCDCTL_API=${ETCDCTL_API:-3}
ENDPOINTS=${ETCD_ENDPOINTS:-"https://127.0.0.1:2379"}
CACERT=${ETCD_CACERT:-"/etc/kubernetes/pki/etcd/ca.crt"}
CERT=${ETCD_CERT:-"/etc/kubernetes/pki/etcd/server.crt"}
KEY=${ETCD_KEY:-"/etc/kubernetes/pki/etcd/server.key"}
BACKUP_DIR=${BACKUP_DIR:-"/var/lib/etcd-backups"}
CLUSTER_NAME=${CLUSTER_NAME:-"kubernetes"}
RETENTION_DAYS=${RETENTION_DAYS:-30}
STORAGE_TYPE=${STORAGE_TYPE:-"local"}
S3_BUCKET=${S3_BUCKET:-""}
S3_PREFIX=${S3_PREFIX:-"etcd-backups"}
COMPRESSION=${COMPRESSION:-"true"}
ENCRYPTION=${ENCRYPTION:-"false"}
ENCRYPTION_KEY=${ENCRYPTION_KEY:-""}
TEST_MODE=${TEST_MODE:-"false"}

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_debug() {
    if [ "${DEBUG:-false}" = "true" ]; then
        echo -e "${BLUE}[DEBUG]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
    fi
}

# Print usage
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Production-grade etcd backup script for Kubernetes

OPTIONS:
    -e, --endpoints ENDPOINTS       etcd endpoints (default: https://127.0.0.1:2379)
    -c, --cacert PATH              CA certificate path (default: /etc/kubernetes/pki/etcd/ca.crt)
    -t, --cert PATH                Client certificate path (default: /etc/kubernetes/pki/etcd/server.crt)
    -k, --key PATH                 Client key path (default: /etc/kubernetes/pki/etcd/server.key)
    -d, --backup-dir PATH          Local backup directory (default: /var/lib/etcd-backups)
    -n, --cluster-name NAME        Cluster name for identification (default: kubernetes)
    -r, --retention-days DAYS      Backup retention period (default: 30)
    -s, --storage TYPE             Storage type: local, s3, gcs, azure (default: local)
    -b, --s3-bucket BUCKET         S3 bucket name (required for s3 storage)
    -p, --s3-prefix PREFIX         S3 path prefix (default: etcd-backups)
    --compression                  Enable compression (default: true)
    --no-compression              Disable compression
    --encryption                  Enable encryption
    --encryption-key KEY          Encryption key for backup
    --test-mode                   Test mode (uses test cluster)
    --debug                       Enable debug logging
    -h, --help                    Show this help message

EXAMPLES:
    # Basic local backup
    $0

    # Backup to S3
    $0 --storage s3 --s3-bucket my-etcd-backups

    # Backup with custom retention
    $0 --retention-days 60 --cluster-name production

    # Backup with encryption
    $0 --encryption --encryption-key "my-secret-key"

ENVIRONMENT VARIABLES:
    ETCDCTL_API              etcd API version (default: 3)
    ETCD_ENDPOINTS          etcd endpoints
    ETCD_CACERT             CA certificate path
    ETCD_CERT               Client certificate path
    ETCD_KEY                Client key path
    BACKUP_DIR              Backup directory
    CLUSTER_NAME            Cluster name
    RETENTION_DAYS          Retention period
    STORAGE_TYPE            Storage type
    S3_BUCKET               S3 bucket name
    AWS_ACCESS_KEY_ID       AWS access key (for S3)
    AWS_SECRET_ACCESS_KEY   AWS secret key (for S3)
    AWS_DEFAULT_REGION      AWS region (for S3)

EOF
    exit 1
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -e|--endpoints)
                ENDPOINTS="$2"
                shift 2
                ;;
            -c|--cacert)
                CACERT="$2"
                shift 2
                ;;
            -t|--cert)
                CERT="$2"
                shift 2
                ;;
            -k|--key)
                KEY="$2"
                shift 2
                ;;
            -d|--backup-dir)
                BACKUP_DIR="$2"
                shift 2
                ;;
            -n|--cluster-name)
                CLUSTER_NAME="$2"
                shift 2
                ;;
            -r|--retention-days)
                RETENTION_DAYS="$2"
                shift 2
                ;;
            -s|--storage)
                STORAGE_TYPE="$2"
                shift 2
                ;;
            -b|--s3-bucket)
                S3_BUCKET="$2"
                shift 2
                ;;
            -p|--s3-prefix)
                S3_PREFIX="$2"
                shift 2
                ;;
            --compression)
                COMPRESSION="true"
                shift
                ;;
            --no-compression)
                COMPRESSION="false"
                shift
                ;;
            --encryption)
                ENCRYPTION="true"
                shift
                ;;
            --encryption-key)
                ENCRYPTION_KEY="$2"
                shift 2
                ;;
            --test-mode)
                TEST_MODE="true"
                shift
                ;;
            --debug)
                DEBUG="true"
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                ;;
        esac
    done
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if etcdctl is available
    if ! command -v etcdctl &> /dev/null; then
        log_error "etcdctl not found! Please install etcd client."
        exit 1
    fi
    
    # Check etcd certificates
    for cert_file in "$CACERT" "$CERT" "$KEY"; do
        if [ ! -f "$cert_file" ]; then
            log_error "Certificate file not found: $cert_file"
            exit 1
        fi
    done
    
    # Check storage-specific requirements
    if [ "$STORAGE_TYPE" = "s3" ]; then
        if [ -z "$S3_BUCKET" ]; then
            log_error "S3 bucket name is required for S3 storage"
            exit 1
        fi
        if ! command -v aws &> /dev/null; then
            log_error "AWS CLI not found! Please install AWS CLI."
            exit 1
        fi
    fi
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR"
    
    log_info "Prerequisites check passed"
}

# Check etcd health
check_etcd_health() {
    log_info "Checking etcd cluster health..."
    
    if etcdctl endpoint health \
        --endpoints="$ENDPOINTS" \
        --cacert="$CACERT" \
        --cert="$CERT" \
        --key="$KEY" 2>&1 | grep -q "is healthy"; then
        log_info "✓ etcd cluster is healthy"
        return 0
    else
        log_error "✗ etcd cluster health check failed!"
        return 1
    fi
}

# Get etcd cluster info
get_cluster_info() {
    log_info "Gathering etcd cluster information..."
    
    echo ""
    echo "=== etcd Cluster Members ==="
    etcdctl member list \
        --endpoints="$ENDPOINTS" \
        --cacert="$CACERT" \
        --cert="$CERT" \
        --key="$KEY" \
        --write-out=table || log_warn "Failed to get member list"
    
    echo ""
    echo "=== etcd Cluster Status ==="
    etcdctl endpoint status \
        --endpoints="$ENDPOINTS" \
        --cacert="$CACERT" \
        --cert="$CERT" \
        --key="$KEY" \
        --write-out=table || log_warn "Failed to get endpoint status"
    echo ""
}

# Take etcd snapshot
take_snapshot() {
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local snapshot_name="etcd-snapshot-${CLUSTER_NAME}-${timestamp}.db"
    local snapshot_path="${BACKUP_DIR}/${snapshot_name}"
    
    log_info "Taking etcd snapshot: $snapshot_name"
    
    local start_time=$(date +%s)
    
    if etcdctl snapshot save "$snapshot_path" \
        --endpoints="$ENDPOINTS" \
        --cacert="$CACERT" \
        --cert="$CERT" \
        --key="$KEY"; then
        
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        log_info "✓ Snapshot saved successfully in ${duration} seconds"
        
        # Get snapshot size
        local snapshot_size=$(du -h "$snapshot_path" | cut -f1)
        log_info "Snapshot size: $snapshot_size"
        
        # Verify snapshot
        log_info "Verifying snapshot integrity..."
        if etcdctl snapshot status "$snapshot_path" --write-out=table; then
            log_info "✓ Snapshot verification passed"
        else
            log_error "✗ Snapshot verification failed!"
            return 1
        fi
        
        # Get total keys count
        local total_keys=$(etcdctl get / --prefix --keys-only \
            --endpoints="$ENDPOINTS" \
            --cacert="$CACERT" \
            --cert="$CERT" \
            --key="$KEY" 2>/dev/null | wc -l)
        log_info "Total keys backed up: $total_keys"
        
        # Compress if enabled
        if [ "$COMPRESSION" = "true" ]; then
            log_info "Compressing snapshot..."
            gzip -f "$snapshot_path"
            snapshot_path="${snapshot_path}.gz"
            local compressed_size=$(du -h "$snapshot_path" | cut -f1)
            log_info "Compressed size: $compressed_size"
        fi
        
        # Encrypt if enabled
        if [ "$ENCRYPTION" = "true" ] && [ -n "$ENCRYPTION_KEY" ]; then
            log_info "Encrypting snapshot..."
            openssl enc -aes-256-cbc -salt -in "$snapshot_path" \
                -out "${snapshot_path}.enc" -k "$ENCRYPTION_KEY"
            rm -f "$snapshot_path"
            snapshot_path="${snapshot_path}.enc"
            log_info "✓ Snapshot encrypted"
        fi
        
        # Create metadata file
        create_metadata "$snapshot_name" "$snapshot_path" "$duration" "$total_keys"
        
        # Upload to storage
        upload_to_storage "$snapshot_path"
        
        # Cleanup old backups
        cleanup_old_backups
        
        echo ""
        log_info "=========================================="
        log_info "Backup completed successfully!"
        log_info "Snapshot: $(basename $snapshot_path)"
        log_info "Location: $snapshot_path"
        log_info "Duration: ${duration}s"
        log_info "=========================================="
        echo ""
        
        return 0
    else
        log_error "Failed to take etcd snapshot!"
        return 1
    fi
}

# Create metadata file
create_metadata() {
    local snapshot_name=$1
    local snapshot_path=$2
    local duration=$3
    local total_keys=$4
    
    local metadata_file="${snapshot_path}.metadata.json"
    
    cat > "$metadata_file" <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "cluster_name": "${CLUSTER_NAME}",
  "snapshot_file": "$(basename $snapshot_path)",
  "size_bytes": $(stat -c%s "$snapshot_path" 2>/dev/null || stat -f%z "$snapshot_path"),
  "duration_seconds": ${duration},
  "total_keys": ${total_keys},
  "etcd_version": "$(etcdctl version | head -1 | awk '{print $3}')",
  "compression": ${COMPRESSION},
  "encryption": ${ENCRYPTION},
  "storage_type": "${STORAGE_TYPE}",
  "endpoints": "${ENDPOINTS}",
  "kubernetes_version": "$(kubectl version --short 2>/dev/null | grep Server | awk '{print $3}' || echo 'N/A')"
}
EOF
    
    log_debug "Metadata created: $metadata_file"
}

# Upload to storage
upload_to_storage() {
    local snapshot_path=$1
    local snapshot_name=$(basename "$snapshot_path")
    
    case "$STORAGE_TYPE" in
        local)
            log_info "Storage type: local (no upload needed)"
            ;;
        s3)
            upload_to_s3 "$snapshot_path" "$snapshot_name"
            ;;
        gcs)
            upload_to_gcs "$snapshot_path" "$snapshot_name"
            ;;
        azure)
            upload_to_azure "$snapshot_path" "$snapshot_name"
            ;;
        *)
            log_warn "Unknown storage type: $STORAGE_TYPE"
            ;;
    esac
}

# Upload to S3
upload_to_s3() {
    local snapshot_path=$1
    local snapshot_name=$2
    
    log_info "Uploading to S3: s3://${S3_BUCKET}/${S3_PREFIX}/${CLUSTER_NAME}/"
    
    local s3_path="s3://${S3_BUCKET}/${S3_PREFIX}/${CLUSTER_NAME}/$(date +%Y/%m/%d)/${snapshot_name}"
    
    if aws s3 cp "$snapshot_path" "$s3_path" \
        --storage-class STANDARD_IA \
        --server-side-encryption AES256 \
        --only-show-errors; then
        log_info "✓ Uploaded successfully to: $s3_path"
        
        # Upload metadata
        aws s3 cp "${snapshot_path}.metadata.json" "${s3_path}.metadata.json" \
            --only-show-errors 2>/dev/null || true
    else
        log_error "Failed to upload to S3"
        return 1
    fi
}

# Upload to GCS
upload_to_gcs() {
    local snapshot_path=$1
    local snapshot_name=$2
    
    log_info "Uploading to Google Cloud Storage..."
    
    if command -v gsutil &> /dev/null; then
        gsutil cp "$snapshot_path" "gs://${S3_BUCKET}/${S3_PREFIX}/${CLUSTER_NAME}/$(date +%Y/%m/%d)/${snapshot_name}"
        log_info "✓ Uploaded successfully to GCS"
    else
        log_error "gsutil not found!"
        return 1
    fi
}

# Upload to Azure
upload_to_azure() {
    local snapshot_path=$1
    local snapshot_name=$2
    
    log_info "Uploading to Azure Blob Storage..."
    
    if command -v az &> /dev/null; then
        az storage blob upload \
            --file "$snapshot_path" \
            --container-name "${S3_BUCKET}" \
            --name "${S3_PREFIX}/${CLUSTER_NAME}/$(date +%Y/%m/%d)/${snapshot_name}"
        log_info "✓ Uploaded successfully to Azure"
    else
        log_error "Azure CLI not found!"
        return 1
    fi
}

# Cleanup old backups
cleanup_old_backups() {
    log_info "Cleaning up backups older than ${RETENTION_DAYS} days..."
    
    # Local cleanup
    find "$BACKUP_DIR" -name "etcd-snapshot-*.db*" -type f -mtime +"$RETENTION_DAYS" -delete 2>/dev/null || true
    find "$BACKUP_DIR" -name "*.metadata.json" -type f -mtime +"$RETENTION_DAYS" -delete 2>/dev/null || true
    
    # S3 cleanup
    if [ "$STORAGE_TYPE" = "s3" ] && [ -n "$S3_BUCKET" ]; then
        log_info "Cleaning up old S3 backups..."
        local cutoff_date=$(date -d "${RETENTION_DAYS} days ago" +%Y-%m-%d 2>/dev/null || date -v-${RETENTION_DAYS}d +%Y-%m-%d)
        
        aws s3 ls "s3://${S3_BUCKET}/${S3_PREFIX}/${CLUSTER_NAME}/" --recursive | \
            awk '{if ($1 < "'$cutoff_date'") print $4}' | \
            while read file; do
                aws s3 rm "s3://${S3_BUCKET}/${file}" --only-show-errors || true
            done
    fi
    
    log_info "✓ Cleanup completed"
}

# Main function
main() {
    echo ""
    echo "=========================================="
    echo "  etcd Backup Script v1.0.0"
    echo "=========================================="
    echo ""
    
    parse_args "$@"
    check_prerequisites
    
    if ! check_etcd_health; then
        log_error "Aborting backup due to unhealthy etcd cluster"
        exit 1
    fi
    
    get_cluster_info
    
    if take_snapshot; then
        log_info "Backup operation completed successfully!"
        exit 0
    else
        log_error "Backup operation failed!"
        exit 1
    fi
}

# Run main function
main "$@"
