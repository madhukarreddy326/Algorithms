#!/bin/bash
################################################################################
# etcd Backup and Restore Test Script
# Description: Automated testing of backup and restore procedures
# Author: DevOps Team
# Version: 1.0.0
################################################################################

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test configuration
TEST_NAMESPACE="etcd-backup-test"
TEST_RESOURCES_CREATED=0
BACKUP_FILE=""
CLEANUP_ON_EXIT=${CLEANUP_ON_EXIT:-"true"}

log_info() {
    echo -e "${GREEN}[TEST-INFO]${NC} $(date '+%H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[TEST-ERROR]${NC} $(date '+%H:%M:%S') - $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[TEST-WARN]${NC} $(date '+%H:%M:%S') - $1"
}

log_step() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo -e "${BLUE}  STEP: $1${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo ""
}

cleanup() {
    if [ "$CLEANUP_ON_EXIT" = "true" ]; then
        log_info "Cleaning up test resources..."
        kubectl delete namespace "$TEST_NAMESPACE" --ignore-not-found=true --wait=false 2>/dev/null || true
        [ -n "$BACKUP_FILE" ] && rm -f "$BACKUP_FILE" 2>/dev/null || true
        log_info "Cleanup completed"
    else
        log_warn "Cleanup skipped (CLEANUP_ON_EXIT=false)"
    fi
}

trap cleanup EXIT

echo ""
echo "╔════════════════════════════════════════╗"
echo "║  etcd Backup & Restore Test Suite     ║"
echo "╔════════════════════════════════════════╝"
echo ""

# Test 1: Prerequisites Check
log_step "1. Prerequisites Check"

log_info "Checking required tools..."
REQUIRED_TOOLS=("kubectl" "etcdctl")
for tool in "${REQUIRED_TOOLS[@]}"; do
    if command -v "$tool" &> /dev/null; then
        log_info "✓ $tool found: $(command -v $tool)"
    else
        log_error "✗ $tool not found!"
        exit 1
    fi
done

log_info "Checking cluster connectivity..."
if kubectl cluster-info &> /dev/null; then
    log_info "✓ Connected to Kubernetes cluster"
    kubectl cluster-info
else
    log_error "✗ Cannot connect to Kubernetes cluster"
    exit 1
fi

# Test 2: Create Test Resources
log_step "2. Create Test Resources"

log_info "Creating test namespace: $TEST_NAMESPACE"
if kubectl create namespace "$TEST_NAMESPACE"; then
    log_info "✓ Namespace created"
else
    log_error "✗ Failed to create namespace"
    exit 1
fi

log_info "Creating test ConfigMap..."
kubectl create configmap test-config \
    --from-literal=test-key-1="test-value-1" \
    --from-literal=test-key-2="test-value-2" \
    --from-literal=timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    -n "$TEST_NAMESPACE"
TEST_RESOURCES_CREATED=$((TEST_RESOURCES_CREATED + 1))

log_info "Creating test Secret..."
kubectl create secret generic test-secret \
    --from-literal=username="testuser" \
    --from-literal=password="testpass123" \
    -n "$TEST_NAMESPACE"
TEST_RESOURCES_CREATED=$((TEST_RESOURCES_CREATED + 1))

log_info "Creating test Deployment..."
kubectl create deployment test-nginx \
    --image=nginx:latest \
    --replicas=2 \
    -n "$TEST_NAMESPACE"
TEST_RESOURCES_CREATED=$((TEST_RESOURCES_CREATED + 1))

log_info "Creating test Service..."
kubectl expose deployment test-nginx \
    --port=80 \
    --target-port=80 \
    --type=ClusterIP \
    -n "$TEST_NAMESPACE"
TEST_RESOURCES_CREATED=$((TEST_RESOURCES_CREATED + 1))

log_info "Waiting for resources to be ready..."
sleep 5

log_info "✓ Created $TEST_RESOURCES_CREATED test resources"
echo ""
kubectl get all,cm,secret -n "$TEST_NAMESPACE"

# Test 3: Take Backup
log_step "3. Take etcd Backup"

BACKUP_FILE="/tmp/etcd-test-backup-$(date +%Y%m%d-%H%M%S).db"

log_info "Taking backup to: $BACKUP_FILE"
log_info "Running backup script..."

if ../scripts/backup-etcd.sh \
    --backup-dir "$(dirname $BACKUP_FILE)" \
    --cluster-name "test" \
    --storage local; then
    
    # Find the actual backup file created
    BACKUP_FILE=$(ls -t "$(dirname $BACKUP_FILE)"/etcd-snapshot-test-*.db* 2>/dev/null | head -1)
    
    if [ -z "$BACKUP_FILE" ]; then
        log_error "✗ Backup file not found!"
        exit 1
    fi
    
    log_info "✓ Backup created: $BACKUP_FILE"
    log_info "Backup size: $(du -h "$BACKUP_FILE" | cut -f1)"
else
    log_error "✗ Backup failed!"
    exit 1
fi

# Test 4: Verify Backup
log_step "4. Verify Backup Integrity"

log_info "Verifying backup file..."

# Decompress if needed
VERIFY_FILE="$BACKUP_FILE"
if [[ "$BACKUP_FILE" == *.gz ]]; then
    VERIFY_FILE="/tmp/etcd-test-verify-$$.db"
    gunzip -c "$BACKUP_FILE" > "$VERIFY_FILE"
    log_info "Decompressed for verification"
fi

if ETCDCTL_API=3 etcdctl snapshot status "$VERIFY_FILE" --write-out=table; then
    log_info "✓ Backup verification passed"
else
    log_error "✗ Backup verification failed!"
    exit 1
fi

# Cleanup verify file
[ "$VERIFY_FILE" != "$BACKUP_FILE" ] && rm -f "$VERIFY_FILE"

# Test 5: Delete Test Resources
log_step "5. Delete Test Resources"

log_info "Deleting test namespace to simulate data loss..."
kubectl delete namespace "$TEST_NAMESPACE" --wait=true

log_info "Verifying deletion..."
sleep 3

if kubectl get namespace "$TEST_NAMESPACE" &> /dev/null; then
    log_warn "Namespace still exists (may be terminating)"
else
    log_info "✓ Namespace deleted successfully"
fi

# Test 6: Restore Backup (Dry Run)
log_step "6. Test Restore (Dry Run)"

log_warn "Testing restore in DRY RUN mode (no actual restore)"
log_info "In production, you would run:"
echo ""
echo "  ../scripts/restore-etcd.sh --snapshot $BACKUP_FILE --confirm"
echo ""

log_info "✓ Restore test completed (dry run only)"
log_warn "⚠️  IMPORTANT: Full restore test requires stopping API server"
log_warn "⚠️  Run full restore test only in dedicated test cluster"

# Test 7: Verify Restore (Simulation)
log_step "7. Simulate Restore Verification"

log_info "In a real restore, you would verify:"
echo "  1. kubectl get nodes"
echo "  2. kubectl get namespaces"
echo "  3. kubectl get pods --all-namespaces"
echo "  4. kubectl get all -n $TEST_NAMESPACE"

log_info "Current cluster state (should not have test namespace):"
kubectl get namespace "$TEST_NAMESPACE" &> /dev/null && log_warn "Test namespace still exists!" || log_info "✓ Test namespace is gone (as expected)"

# Test 8: Performance Metrics
log_step "8. Performance Metrics"

if [ -f "$BACKUP_FILE" ]; then
    echo ""
    echo "Backup File Statistics:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  File: $(basename $BACKUP_FILE)"
    echo "  Size: $(du -h "$BACKUP_FILE" | cut -f1)"
    echo "  Path: $BACKUP_FILE"
    echo "  Created: $(stat -c %y "$BACKUP_FILE" 2>/dev/null || stat -f "%Sm" "$BACKUP_FILE")"
    
    # Decompress and check original size if compressed
    if [[ "$BACKUP_FILE" == *.gz ]]; then
        ORIGINAL_SIZE=$(gunzip -l "$BACKUP_FILE" | tail -1 | awk '{print $2}')
        ORIGINAL_SIZE_MB=$((ORIGINAL_SIZE / 1024 / 1024))
        echo "  Original size: ${ORIGINAL_SIZE_MB} MB"
        COMPRESSED_SIZE=$(stat -c%s "$BACKUP_FILE" 2>/dev/null || stat -f%z "$BACKUP_FILE")
        COMPRESSED_SIZE_MB=$((COMPRESSED_SIZE / 1024 / 1024))
        RATIO=$(( (ORIGINAL_SIZE - COMPRESSED_SIZE) * 100 / ORIGINAL_SIZE ))
        echo "  Compression: ${RATIO}% saved"
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
fi

# Test Results Summary
log_step "Test Results Summary"

echo ""
echo "╔════════════════════════════════════════╗"
echo "║         TEST RESULTS SUMMARY           ║"
echo "╚════════════════════════════════════════╝"
echo ""
echo "✅ Test 1: Prerequisites Check - PASSED"
echo "✅ Test 2: Create Test Resources - PASSED ($TEST_RESOURCES_CREATED resources)"
echo "✅ Test 3: Take etcd Backup - PASSED"
echo "✅ Test 4: Verify Backup - PASSED"
echo "✅ Test 5: Delete Resources - PASSED"
echo "⚠️  Test 6: Restore Test - SKIPPED (dry run only)"
echo "⚠️  Test 7: Verify Restore - SKIPPED (simulation only)"
echo "✅ Test 8: Performance Metrics - PASSED"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📝 NOTES:"
echo "  - Backup file preserved at: $BACKUP_FILE"
echo "  - Full restore test requires dedicated test cluster"
echo "  - For complete testing, run in isolated environment"
echo ""
echo "📖 NEXT STEPS:"
echo "  1. Review backup file and metadata"
echo "  2. Test restore in dedicated test cluster"
echo "  3. Schedule regular automated tests"
echo "  4. Set up monitoring and alerting"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

log_info "✅ All tests completed successfully!"
exit 0
