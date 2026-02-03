#!/bin/bash
################################################################################
# etcd Backup Cleanup Script
# Description: Clean up old etcd backups based on retention policy
# Author: DevOps Team
# Version: 1.0.0
################################################################################

set -euo pipefail

# Default configuration
BACKUP_DIR=${BACKUP_DIR:-"/var/lib/etcd-backups"}
RETENTION_DAYS=${RETENTION_DAYS:-30}
S3_BUCKET=${S3_BUCKET:-""}
S3_PREFIX=${S3_PREFIX:-"etcd-backups"}
CLUSTER_NAME=${CLUSTER_NAME:-"kubernetes"}
DRY_RUN=${DRY_RUN:-"false"}

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Clean up old etcd backups based on retention policy

OPTIONS:
    -d, --backup-dir DIR      Backup directory (default: /var/lib/etcd-backups)
    -r, --retention-days DAYS Retention period in days (default: 30)
    -b, --s3-bucket BUCKET    S3 bucket for cloud cleanup
    -p, --s3-prefix PREFIX    S3 prefix (default: etcd-backups)
    -n, --cluster-name NAME   Cluster name (default: kubernetes)
    --dry-run                 Show what would be deleted without deleting
    -h, --help                Show this help message

EXAMPLES:
    # Local cleanup
    $0 --retention-days 30

    # S3 cleanup
    $0 --s3-bucket my-etcd-backups --retention-days 60

    # Dry run
    $0 --dry-run

EOF
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--backup-dir)
            BACKUP_DIR="$2"
            shift 2
            ;;
        -r|--retention-days)
            RETENTION_DAYS="$2"
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
        -n|--cluster-name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN="true"
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

echo ""
log_info "=========================================="
log_info "etcd Backup Cleanup"
log_info "=========================================="
echo ""

if [ "$DRY_RUN" = "true" ]; then
    log_warn "DRY RUN MODE - No files will be deleted"
    echo ""
fi

# Local cleanup
if [ -d "$BACKUP_DIR" ]; then
    log_info "Cleaning up local backups older than ${RETENTION_DAYS} days..."
    log_info "Directory: $BACKUP_DIR"
    
    OLD_FILES=$(find "$BACKUP_DIR" -name "etcd-snapshot-*.db*" -type f -mtime +"$RETENTION_DAYS" 2>/dev/null || true)
    OLD_METADATA=$(find "$BACKUP_DIR" -name "*.metadata.json" -type f -mtime +"$RETENTION_DAYS" 2>/dev/null || true)
    
    COUNT=0
    TOTAL_SIZE=0
    
    for file in $OLD_FILES $OLD_METADATA; do
        if [ -f "$file" ]; then
            SIZE=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo 0)
            TOTAL_SIZE=$((TOTAL_SIZE + SIZE))
            COUNT=$((COUNT + 1))
            
            log_info "  - $file ($(du -h "$file" | cut -f1))"
            
            if [ "$DRY_RUN" != "true" ]; then
                rm -f "$file"
            fi
        fi
    done
    
    if [ $COUNT -eq 0 ]; then
        log_info "  No old backups found"
    else
        TOTAL_SIZE_MB=$((TOTAL_SIZE / 1024 / 1024))
        if [ "$DRY_RUN" = "true" ]; then
            log_info "Would delete $COUNT files (${TOTAL_SIZE_MB} MB)"
        else
            log_info "Deleted $COUNT files (${TOTAL_SIZE_MB} MB freed)"
        fi
    fi
else
    log_warn "Local backup directory not found: $BACKUP_DIR"
fi

echo ""

# S3 cleanup
if [ -n "$S3_BUCKET" ]; then
    if command -v aws &> /dev/null; then
        log_info "Cleaning up S3 backups older than ${RETENTION_DAYS} days..."
        log_info "Bucket: s3://${S3_BUCKET}/${S3_PREFIX}/${CLUSTER_NAME}/"
        
        CUTOFF_DATE=$(date -d "${RETENTION_DAYS} days ago" +%Y-%m-%d 2>/dev/null || date -v-${RETENTION_DAYS}d +%Y-%m-%d)
        
        COUNT=0
        aws s3 ls "s3://${S3_BUCKET}/${S3_PREFIX}/${CLUSTER_NAME}/" --recursive | \
            awk '{if ($1 < "'$CUTOFF_DATE'") print $4}' | \
            while read file; do
                COUNT=$((COUNT + 1))
                log_info "  - s3://${S3_BUCKET}/${file}"
                
                if [ "$DRY_RUN" != "true" ]; then
                    aws s3 rm "s3://${S3_BUCKET}/${file}" --only-show-errors || true
                fi
            done
        
        if [ "$DRY_RUN" = "true" ]; then
            log_info "Would delete old S3 backups"
        else
            log_info "S3 cleanup completed"
        fi
    else
        log_error "AWS CLI not found for S3 cleanup"
    fi
fi

echo ""
log_info "=========================================="
log_info "Cleanup completed!"
log_info "=========================================="
echo ""

exit 0
