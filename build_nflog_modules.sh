#!/bin/bash
set -euo pipefail

# =============================================================================
#  Complete Kernel Module Builder for CONFIG_NETFILTER_NETLINK_LOG
#  and CONFIG_NETFILTER_XT_TARGET_NFLOG
#  Target: Jetson (kernel 6.8.12-1021-tegra, L4T R39.2.1, Ubuntu 24.04)
# =============================================================================

# --- Variables ---
KERNEL_VERSION=$(uname -r)
BUILD_DIR="$HOME/kernel-build"
KERNEL_SOURCE_DIR="$BUILD_DIR/Linux_for_Tegra/source/kernel"
MODULES_TARGET_DIR="/lib/modules/$KERNEL_VERSION/kernel/net/netfilter"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()   { echo -e "${GREEN}[INFO]${NC}   $1"; }
warn()   { echo -e "${YELLOW}[WARN]${NC}   $1"; }
error()  { echo -e "${RED}[ERROR]${NC}  $1" >&2; exit 1; }
header() { echo -e "${BLUE}\n==> $1${NC}"; }

# --- Main Script ---
main() {
    header "Kernel Module Builder for NFLOG (L4T R39.2.1)"

    # =====================================================================
    # STEP 0: Validate environment
    # =====================================================================
    if [ "$(id -u)" -ne 0 ]; then
        error "This script must be run as root. Use: sudo $0"
    fi

    info "Target kernel: $KERNEL_VERSION"

    # =====================================================================
    # STEP 1: Check for existing kernel source
    # =====================================================================
    if [ ! -d "$KERNEL_SOURCE_DIR" ]; then
        error "Kernel source not found at: $KERNEL_SOURCE_DIR"
    fi

    if [ ! -f "$KERNEL_SOURCE_DIR/Makefile" ]; then
        error "No Makefile in $KERNEL_SOURCE_DIR - kernel source is incomplete"
    fi

    if [ ! -d "$KERNEL_SOURCE_DIR/net/netfilter" ]; then
        error "No net/netfilter directory in $KERNEL_SOURCE_DIR"
    fi

    info "Using existing kernel source: $KERNEL_SOURCE_DIR"

    # =====================================================================
    # STEP 2: Install build dependencies
    # =====================================================================
    header "Installing build dependencies..."
    apt-get update -qq 2>/dev/null || warn "apt update failed (may be offline)"
    apt-get install -y -qq build-essential libssl-dev bc kmod 2>/dev/null || \
        warn "Some dependencies may be missing, continuing..."

    # =====================================================================
    # STEP 3: Configure kernel
    # =====================================================================
    header "Configuring kernel..."

    cd "$KERNEL_SOURCE_DIR"

    # Copy current kernel config
    if [ ! -f .config ]; then
        info "Copying current kernel config..."
        gunzip -c /proc/config.gz > .config || error "Failed to read /proc/config.gz"
    else
        info "Using existing .config"
    fi

    # Enable the two modules
    info "Enabling CONFIG_NETFILTER_NETLINK_LOG and CONFIG_NETFILTER_XT_TARGET_NFLOG..."
    sed -i 's/^# CONFIG_NETFILTER_NETLINK_LOG is not set/CONFIG_NETFILTER_NETLINK_LOG=m/' .config
    sed -i 's/^# CONFIG_NETFILTER_XT_TARGET_NFLOG is not set/CONFIG_NETFILTER_XT_TARGET_NFLOG=m/' .config

    # Disable module signing to avoid openssl issues
    sed -i 's/^CONFIG_MODULE_SIG=.*/# CONFIG_MODULE_SIG is not set/' .config
    sed -i 's/^CONFIG_MODULE_SIG_FORMAT=.*/# CONFIG_MODULE_SIG_FORMAT is not set/' .config
    sed -i 's/^CONFIG_MODULE_SIG_ALL=.*/# CONFIG_MODULE_SIG_ALL is not set/' .config

    # Run olddefconfig to sync
    info "Running olddefconfig..."
    make olddefconfig || error "olddefconfig failed"

    # =====================================================================
    # STEP 4: Build modules
    # =====================================================================
    header "Building kernel modules (10-30 minutes)..."

    info "Running modules_prepare..."
    make -j$(nproc) modules_prepare || error "modules_prepare failed"

    info "Building netfilter modules..."
    make -j$(nproc) M=net/netfilter modules || error "Build failed"

    # Verify modules were built
    if [ ! -f "net/netfilter/nfnetlink_log.ko" ]; then
        error "nfnetlink_log.ko not built. Check for errors above."
    fi
    if [ ! -f "net/netfilter/xt_NFLOG.ko" ]; then
        error "xt_NFLOG.ko not built. Check for errors above."
    fi

    info "Modules built successfully!"

    # =====================================================================
    # STEP 5: Install modules
    # =====================================================================
    header "Installing modules..."

    mkdir -p "$MODULES_TARGET_DIR"
    cp net/netfilter/nfnetlink_log.ko "$MODULES_TARGET_DIR/"
    cp net/netfilter/xt_NFLOG.ko "$MODULES_TARGET_DIR/"

    info "Running depmod..."
    depmod -a || error "depmod failed"

    # =====================================================================
    # STEP 6: Load modules
    # =====================================================================
    header "Loading modules..."

    modprobe nfnetlink_log || warn "Failed to load nfnetlink_log.ko"
    modprobe xt_NFLOG || warn "Failed to load xt_NFLOG.ko"

    # =====================================================================
    # STEP 7: Verify
    # =====================================================================
    header "Verification"

    info "Checking loaded modules..."
    if lsmod | grep -q nfnetlink_log; then
        info "✓ nfnetlink_log module loaded"
    else
        warn "✗ nfnetlink_log module NOT loaded"
    fi

    if lsmod | grep -q xt_NFLOG; then
        info "✓ xt_NFLOG module loaded"
    else
        warn "✗ xt_NFLOG module NOT loaded"
    fi

    # =====================================================================
    # STEP 8: Success message
    # =====================================================================
    header "SUCCESS!"

    info "Modules installed to: $MODULES_TARGET_DIR"
    info ""
    info "Commands:"
    info "  Load:   sudo modprobe nfnetlink_log xt_NFLOG"
    info "  Unload: sudo modprobe -r nfnetlink_log xt_NFLOG"
    info "  Check:  lsmod | grep -E 'nfnetlink_log|xt_NFLOG'"
    info ""
}

# Run main
main "$@"