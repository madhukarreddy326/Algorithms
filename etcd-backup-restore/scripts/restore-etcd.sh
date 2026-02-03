#!/bin/bash
################################################################################
# etcd Restore Script
# Description: Production-grade etcd restore script with safety checks
# Author: DevOps Team
# Version: 1.0.0
# WARNING: This script will restore etcd data and may cause cluster downtime
################################################################################

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Default configuration
ETCDCTL_API=${ETCDCTL_API:-3}
SNAPSHOT_FILE=""
ETCD_DATA_DIR=${ETCD_DATA_DIR:-"/var/lib/etcd"}
ETCD_NAME=${ETCD_NAME:-"default"}
INITIAL_CLUSTER=${INITIAL_CLUSTER:-""}
INITIAL_ADVERTISE_PEER_URLS=${INITIAL_ADVERTISE_PEER_URLS:-""}
SKIP_HASH_CHECK=${SKIP_HASH_CHECK:-"false"}
BACKUP_CURRENT=${BACKUP_CURRENT:-"true"}
CONFIRM=${CONFIRM:-"false"}
DRY_RUN=${DRY_RUN:-"false"}

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

log_critical() {
    echo -e "${MAGENTA}[CRITICAL]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
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

⚠️  CRITICAL: This script will restore etcd data and may cause cluster downtime ⚠️

IMPORTANT: Before running this script:
  1. Take a backup of current etcd data
  2. Stop the Kubernetes API server
  3. Ensure no applications are writing to the cluster
  4. Test restore in a non-production environment first

OPTIONS:
    -s, --snapshot FILE            Path to snapshot file (required)
    -d, --data-dir DIR            etcd data directory (default: /var/lib/etcd)
    -n, --name NAME               etcd member name (default: default)
    -i, --initial-cluster CLUSTER Initial cluster configuration
    -a, --advertise-urls URLS     Initial advertise peer URLs
    --skip-hash-check             Skip snapshot hash verification
    --no-backup-current           Don't backup current etcd data
    --confirm                     Skip confirmation prompt (use with caution!)
    --dry-run                     Show what would be done without executing
    --debug                       Enable debug logging
    -h, --help                    Show this help message

EXAMPLES:
    # Basic restore (will prompt for confirmation)
    $0 --snapshot /backup/etcd-snapshot-20260203-120000.db

    # Restore with custom data directory
    $0 --snapshot /backup/snapshot.db --data-dir /var/lib/etcd-restore

    # Restore for multi-node cluster
    $0 --snapshot /backup/snapshot.db \\
       --name master-1 \\
       --initial-cluster "master-1=https://10.0.1.10:2380,master-2=https://10.0.1.11:2380" \\
       --advertise-urls "https://10.0.1.10:2380"

    # Dry run to see what would be done
    $0 --snapshot /backup/snapshot.db --dry-run

RESTORE PROCEDURE:
    1. Verify snapshot file exists and is valid
    2. Backup current etcd data (if requested)
    3. Stop Kubernetes API server
    4. Restore snapshot to new data directory
    5. Update etcd configuration (if needed)
    6. Start etcd and API server
    7. Verify cluster health

SAFETY CHECKS:
    ✓ Snapshot file verification
    ✓ Current data backup
    ✓ Confirmation prompt (unless --confirm is used)
    ✓ Dry-run mode available
    ✓ Detailed logging

ENVIRONMENT VARIABLES:
    ETCDCTL_API              etcd API version (default: 3)
    ETCD_DATA_DIR           etcd data directory
    ETCD_NAME               etcd member name
    INITIAL_CLUSTER         Initial cluster configuration
    BACKUP_CURRENT          Backup current data (default: true)

EOF
    exit 1
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -s|--snapshot)
                SNAPSHOT_FILE="$2"
                shift 2
                ;;
            -d|--data-dir)
                ETCD_DATA_DIR="$2"
                shift 2
                ;;
            -n|--name)
                ETCD_NAME="$2"
                shift 2
                ;;
            -i|--initial-cluster)
                INITIAL_CLUSTER="$2"
                shift 2
                ;;
            -a|--advertise-urls)
                INITIAL_ADVERTISE_PEER_URLS="$2"
                shift 2
                ;;
            --skip-hash-check)
                SKIP_HASH_CHECK="true"
                shift
                ;;
            --no-backup-current)
                BACKUP_CURRENT="false"
                shift
                ;;
            --confirm)
                CONFIRM="true"
                shift
                ;;
            --dry-run)
                DRY_RUN="true"
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
    
    # Check if snapshot file is provided
    if [ -z "$SNAPSHOT_FILE" ]; then
        log_error "Snapshot file is required! Use -s or --snapshot option."
        usage
    fi
    
    # Check if snapshot file exists
    if [ ! -f "$SNAPSHOT_FILE" ]; then
        log_error "Snapshot file not found: $SNAPSHOT_FILE"
        exit 1
    fi
    
    # Check if running as root
    if [ "$EUID" -ne 0 ] && [ "$DRY_RUN" != "true" ]; then
        log_error "This script must be run as root (or use --dry-run)"
        exit 1
    fi
    
    log_info "✓ Prerequisites check passed"
}

# Verify snapshot
verify_snapshot() {
    log_info "Verifying snapshot: $SNAPSHOT_FILE"
    
    # Decompress if needed
    if [[ "$SNAPSHOT_FILE" == *.gz ]]; then
        log_info "Decompressing snapshot..."
        local decompressed="${SNAPSHOT_FILE%.gz}"
        gunzip -c "$SNAPSHOT_FILE" > "$decompressed"
        SNAPSHOT_FILE="$decompressed"
        log_info "Decompressed to: $SNAPSHOT_FILE"
    fi
    
    # Decrypt if needed
    if [[ "$SNAPSHOT_FILE" == *.enc ]]; then
        log_warn "Snapshot is encrypted. Decryption key required."
        if [ -z "${ENCRYPTION_KEY:-}" ]; then
            read -sp "Enter encryption key: " ENCRYPTION_KEY
            echo ""
        fi
        log_info "Decrypting snapshot..."
        local decrypted="${SNAPSHOT_FILE%.enc}"
        openssl enc -d -aes-256-cbc -in "$SNAPSHOT_FILE" -out "$decrypted" -k "$ENCRYPTION_KEY"
        SNAPSHOT_FILE="$decrypted"
        log_info "Decrypted to: $SNAPSHOT_FILE"
    fi
    
    # Get snapshot info
    log_info "Snapshot information:"
    echo ""
    if etcdctl snapshot status "$SNAPSHOT_FILE" --write-out=table; then
        log_info "✓ Snapshot verification passed"
        return 0
    else
        log_error "✗ Snapshot verification failed!"
        return 1
    fi
}

# Backup current etcd data
backup_current_data() {
    if [ "$BACKUP_CURRENT" != "true" ]; then
        log_warn "Skipping backup of current etcd data (--no-backup-current specified)"
        return 0
    fi
    
    if [ ! -d "$ETCD_DATA_DIR" ]; then
        log_warn "Current etcd data directory not found: $ETCD_DATA_DIR"
        return 0
    fi
    
    local backup_dir="/var/lib/etcd-backups/pre-restore-$(date +%Y%m%d-%H%M%S)"
    
    log_info "Backing up current etcd data to: $backup_dir"
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would backup: $ETCD_DATA_DIR -> $backup_dir"
        return 0
    fi
    
    mkdir -p "$(dirname $backup_dir)"
    
    if cp -a "$ETCD_DATA_DIR" "$backup_dir"; then
        log_info "✓ Current data backed up successfully"
        echo ""
        log_info "Backup location: $backup_dir"
        log_info "To rollback this restore, copy this directory back to: $ETCD_DATA_DIR"
        echo ""
        return 0
    else
        log_error "Failed to backup current data!"
        return 1
    fi
}

# Confirmation prompt
confirm_restore() {
    if [ "$CONFIRM" = "true" ]; then
        log_warn "Confirmation skipped (--confirm specified)"
        return 0
    fi
    
    echo ""
    echo "=========================================="
    log_critical "⚠️  WARNING: DESTRUCTIVE OPERATION ⚠️"
    echo "=========================================="
    echo ""
    echo "This operation will:"
    echo "  1. Stop Kubernetes API server"
    echo "  2. Replace current etcd data with snapshot"
    echo "  3. Restart etcd and API server"
    echo "  4. Cause cluster downtime"
    echo ""
    echo "Current etcd data directory: $ETCD_DATA_DIR"
    echo "Snapshot file: $SNAPSHOT_FILE"
    echo "Snapshot date: $(stat -c %y "$SNAPSHOT_FILE" 2>/dev/null || stat -f "%Sm" "$SNAPSHOT_FILE")"
    echo ""
    log_warn "All data created after the snapshot will be LOST!"
    echo ""
    
    read -p "Are you sure you want to continue? (type 'yes' to proceed): " response
    
    if [ "$response" != "yes" ]; then
        log_info "Restore cancelled by user"
        exit 0
    fi
    
    echo ""
    log_info "Restore confirmed by user"
}

# Stop Kubernetes API server
stop_api_server() {
    log_info "Stopping Kubernetes API server..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would stop API server"
        return 0
    fi
    
    local api_server_manifest="/etc/kubernetes/manifests/kube-apiserver.yaml"
    local api_server_backup="/tmp/kube-apiserver.yaml.backup"
    
    if [ -f "$api_server_manifest" ]; then
        mv "$api_server_manifest" "$api_server_backup"
        log_info "✓ API server stopped (manifest moved to: $api_server_backup)"
        
        # Wait for API server to stop
        log_info "Waiting for API server to stop..."
        sleep 10
    else
        log_warn "API server manifest not found at: $api_server_manifest"
        log_warn "You may need to stop the API server manually"
    fi
}

# Restore snapshot
restore_snapshot() {
    log_info "Restoring etcd snapshot..."
    
    local restore_dir="${ETCD_DATA_DIR}.restore"
    
    # Build restore command
    local restore_cmd="etcdctl snapshot restore \"$SNAPSHOT_FILE\" \
        --data-dir=\"$restore_dir\" \
        --name=\"$ETCD_NAME\""
    
    if [ -n "$INITIAL_CLUSTER" ]; then
        restore_cmd="$restore_cmd --initial-cluster=\"$INITIAL_CLUSTER\""
    fi
    
    if [ -n "$INITIAL_ADVERTISE_PEER_URLS" ]; then
        restore_cmd="$restore_cmd --initial-advertise-peer-urls=\"$INITIAL_ADVERTISE_PEER_URLS\""
    fi
    
    if [ "$SKIP_HASH_CHECK" = "true" ]; then
        restore_cmd="$restore_cmd --skip-hash-check"
    fi
    
    log_debug "Restore command: $restore_cmd"
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would execute: $restore_cmd"
        log_info "[DRY-RUN] Would move: $restore_dir -> $ETCD_DATA_DIR"
        return 0
    fi
    
    # Execute restore
    if eval "$restore_cmd"; then
        log_info "✓ Snapshot restored successfully"
        
        # Move restored data to etcd data directory
        log_info "Moving restored data to etcd data directory..."
        
        # Remove old data
        if [ -d "$ETCD_DATA_DIR" ]; then
            rm -rf "$ETCD_DATA_DIR"
        fi
        
        # Move restored data
        mv "$restore_dir" "$ETCD_DATA_DIR"
        
        # Set correct permissions
        chown -R etcd:etcd "$ETCD_DATA_DIR" 2>/dev/null || true
        chmod -R 700 "$ETCD_DATA_DIR" 2>/dev/null || true
        
        log_info "✓ Restored data moved to: $ETCD_DATA_DIR"
        return 0
    else
        log_error "✗ Snapshot restore failed!"
        return 1
    fi
}

# Start API server
start_api_server() {
    log_info "Starting Kubernetes API server..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would start API server"
        return 0
    fi
    
    local api_server_manifest="/etc/kubernetes/manifests/kube-apiserver.yaml"
    local api_server_backup="/tmp/kube-apiserver.yaml.backup"
    
    if [ -f "$api_server_backup" ]; then
        mv "$api_server_backup" "$api_server_manifest"
        log_info "✓ API server manifest restored"
        
        # Wait for API server to start
        log_info "Waiting for API server to start..."
        sleep 20
        
        # Check if API server is running
        if kubectl cluster-info &>/dev/null; then
            log_info "✓ API server is running"
        else
            log_warn "API server may not be fully ready yet"
        fi
    else
        log_warn "API server backup not found. You may need to start it manually."
    fi
}

# Verify restore
verify_restore() {
    log_info "Verifying restore..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would verify cluster health"
        return 0
    fi
    
    echo ""
    log_info "Checking cluster status..."
    
    # Wait a bit for cluster to stabilize
    sleep 5
    
    # Check nodes
    log_info "Cluster nodes:"
    kubectl get nodes 2>/dev/null || log_warn "Failed to get nodes"
    
    echo ""
    log_info "System pods:"
    kubectl get pods -n kube-system 2>/dev/null || log_warn "Failed to get pods"
    
    echo ""
    log_info "Namespaces:"
    kubectl get namespaces 2>/dev/null || log_warn "Failed to get namespaces"
    
    echo ""
}

# Cleanup temporary files
cleanup() {
    log_debug "Cleaning up temporary files..."
    
    # Remove decompressed/decrypted files if they were created
    if [[ "$SNAPSHOT_FILE" == /tmp/* ]]; then
        rm -f "$SNAPSHOT_FILE" 2>/dev/null || true
    fi
}

# Main function
main() {
    # Setup trap for cleanup
    trap cleanup EXIT
    
    echo ""
    echo "=========================================="
    echo "  etcd Restore Script v1.0.0"
    echo "=========================================="
    echo ""
    
    parse_args "$@"
    check_prerequisites
    
    if ! verify_snapshot; then
        log_error "Aborting restore due to snapshot verification failure"
        exit 1
    fi
    
    confirm_restore
    
    if ! backup_current_data; then
        log_error "Failed to backup current data"
        read -p "Continue anyway? (type 'yes'): " response
        if [ "$response" != "yes" ]; then
            exit 1
        fi
    fi
    
    echo ""
    log_info "=========================================="
    log_info "Starting restore process..."
    log_info "=========================================="
    echo ""
    
    stop_api_server
    
    if restore_snapshot; then
        start_api_server
        verify_restore
        
        echo ""
        log_info "=========================================="
        log_info "✓ Restore completed successfully!"
        log_info "=========================================="
        echo ""
        
        log_info "Next steps:"
        echo "  1. Verify all applications are working correctly"
        echo "  2. Check pod status: kubectl get pods --all-namespaces"
        echo "  3. Check for any issues in events: kubectl get events --all-namespaces"
        echo "  4. Monitor cluster health for the next 30 minutes"
        echo ""
        
        if [ "$BACKUP_CURRENT" = "true" ]; then
            log_info "Pre-restore backup available at:"
            ls -d /var/lib/etcd-backups/pre-restore-* 2>/dev/null | tail -1 || echo "  (backup location not found)"
        fi
        
        echo ""
        exit 0
    else
        log_error "=========================================="
        log_error "✗ Restore failed!"
        log_error "=========================================="
        echo ""
        
        log_error "The cluster may be in an inconsistent state!"
        echo ""
        echo "Recovery options:"
        echo "  1. Check etcd logs: journalctl -u etcd"
        echo "  2. Restore from pre-restore backup if available"
        echo "  3. Try restore with --skip-hash-check flag"
        echo "  4. Contact your cluster administrator"
        echo ""
        
        exit 1
    fi
}

# Run main function
main "$@"
