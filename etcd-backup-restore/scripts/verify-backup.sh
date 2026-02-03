#!/bin/bash
################################################################################
# etcd Backup Verification Script
# Description: Verify etcd backup integrity and content
# Author: DevOps Team
# Version: 1.0.0
################################################################################

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SNAPSHOT_FILE=""
VERBOSE=${VERBOSE:-"false"}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Verify etcd backup snapshot integrity and content

OPTIONS:
    -s, --snapshot FILE    Path to snapshot file (required)
    -v, --verbose         Verbose output
    -h, --help            Show this help message

EXAMPLES:
    $0 --snapshot /backup/etcd-snapshot-20260203-120000.db
    $0 -s /backup/snapshot.db -v

EOF
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--snapshot)
            SNAPSHOT_FILE="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE="true"
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

# Check prerequisites
if [ -z "$SNAPSHOT_FILE" ]; then
    log_error "Snapshot file is required!"
    usage
fi

if [ ! -f "$SNAPSHOT_FILE" ]; then
    log_error "Snapshot file not found: $SNAPSHOT_FILE"
    exit 1
fi

if ! command -v etcdctl &> /dev/null; then
    log_error "etcdctl not found!"
    exit 1
fi

echo ""
echo "=========================================="
echo "  etcd Backup Verification"
echo "=========================================="
echo ""

# Decompress if needed
if [[ "$SNAPSHOT_FILE" == *.gz ]]; then
    log_info "Decompressing snapshot for verification..."
    DECOMPRESSED="/tmp/snapshot-verify-$$.db"
    gunzip -c "$SNAPSHOT_FILE" > "$DECOMPRESSED"
    SNAPSHOT_FILE="$DECOMPRESSED"
    trap "rm -f $DECOMPRESSED" EXIT
fi

log_info "Verifying snapshot: $SNAPSHOT_FILE"
echo ""

# Basic file checks
log_info "File Information:"
echo "  Path: $SNAPSHOT_FILE"
echo "  Size: $(du -h "$SNAPSHOT_FILE" | cut -f1)"
echo "  Modified: $(stat -c %y "$SNAPSHOT_FILE" 2>/dev/null || stat -f "%Sm" "$SNAPSHOT_FILE")"
echo ""

# Verify snapshot status
log_info "Snapshot Status:"
ETCDCTL_API=3 etcdctl snapshot status "$SNAPSHOT_FILE" --write-out=table

echo ""
log_info "✓ Snapshot verification completed successfully!"
echo ""

exit 0
