#!/usr/bin/env bash

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Variables
KERNEL_MAJOR=""
KERNEL_MINOR=""
KERNEL_PATCH=""
KERNEL_VERSION=""
CPU_CORES=""
CPU_THREADS=""
CPU_ARCH=""
GPU_VENDOR=""
STORAGE_TYPE=""
DISTRO=""
INIT_SYSTEM=""
BUILD_DIR="$(pwd)/build"


# Logging

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[!]${NC} $*"
}

log_error() {
    echo -e "${RED}[✗]${NC} $*"
}

log_question() {
    echo -e "${CYAN}[?]${NC} $*"
}


# System Detection

detect_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        DISTRO="$ID"
    elif [[ -f /etc/lsb-release ]]; then
        . /etc/lsb-release
        DISTRO="$DISTRIB_ID"
    else
        DISTRO="unknown"
    fi
    echo "$DISTRO" | tr '[:upper:]' '[:lower:]'
}

detect_init_system() {
    if [[ -d /run/systemd/system ]]; then
        echo "systemd"
    elif command -v sv &>/dev/null; then
        echo "runit"
    elif [[ -f /sbin/openrc ]]; then
        echo "openrc"
    else
        echo "unknown"
    fi
}

detect_cpu_info() {
    local cores=$(nproc --all 2>/dev/null || grep -c ^processor /proc/cpuinfo)
    local threads=$cores

    # Detect physical cores
    if [[ -f /proc/cpuinfo ]]; then
        local physical_cores=$(grep "^cpu cores" /proc/cpuinfo | head -1 | awk '{print $4}')
        if [[ -n "$physical_cores" ]]; then
            cores=$physical_cores
            threads=$(nproc --all)
        fi
    fi

    echo "$cores $threads"
}

detect_cpu_arch() {
    local cpu_model=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)

    # Detect CPU architecture
    if echo "$cpu_model" | grep -qi "Intel"; then
        if echo "$cpu_model" | grep -qiE "Core.*(13|14)th"; then
            echo "RAPTORLAKE"
        elif echo "$cpu_model" | grep -qiE "Core.*(12)th"; then
            echo "ALDERLAKE"
        elif echo "$cpu_model" | grep -qiE "Core.*(11)th"; then
            echo "TIGERLAKE"
        elif echo "$cpu_model" | grep -qiE "Core.*(10)th"; then
            echo "COMETLAKE"
        elif echo "$cpu_model" | grep -qiE "Core.*(8|9)th"; then
            echo "COFFEELAKE"
        elif echo "$cpu_model" | grep -qiE "Core.*(6|7)th"; then
            echo "SKYLAKE"
        elif echo "$cpu_model" | grep -qiE "Core.*5th|Broadwell"; then
            echo "BROADWELL"
        elif echo "$cpu_model" | grep -qiE "Core.*4th|Haswell"; then
            echo "HASWELL"
        elif echo "$cpu_model" | grep -qiE "Xeon.*E5.*v4"; then
            echo "BROADWELL"
        elif echo "$cpu_model" | grep -qiE "Xeon.*E5.*v3"; then
            echo "HASWELL"
        else
            echo "GENERIC_CPU"
        fi
    elif echo "$cpu_model" | grep -qi "AMD"; then
        if echo "$cpu_model" | grep -qiE "Ryzen.*(7|9).*[0-9]{4}"; then
            echo "ZEN4"
        elif echo "$cpu_model" | grep -qiE "Ryzen.*(5|7|9).*[5-6][0-9]{3}"; then
            echo "ZEN3"
        elif echo "$cpu_model" | grep -qiE "Ryzen.*(3|5|7|9).*[3-4][0-9]{3}"; then
            echo "ZEN2"
        elif echo "$cpu_model" | grep -qiE "Ryzen.*(3|5|7).*[1-2][0-9]{3}"; then
            echo "ZEN"
        else
            echo "GENERIC_CPU"
        fi
    else
        echo "GENERIC_CPU"
    fi
}

detect_gpu() {
    if lspci 2>/dev/null | grep -qi "VGA.*AMD\|VGA.*Radeon"; then
        echo "amd"
    elif lspci 2>/dev/null | grep -qi "VGA.*NVIDIA"; then
        echo "nvidia"
    elif lspci 2>/dev/null | grep -qi "VGA.*Intel"; then
        echo "intel"
    else
        echo "unknown"
    fi
}

detect_storage() {
    if [[ -d /sys/block/nvme0n1 ]]; then
        echo "nvme"
    elif [[ -d /sys/block/sda ]]; then
        local rotational=$(cat /sys/block/sda/queue/rotational 2>/dev/null || echo "1")
        if [[ "$rotational" == "0" ]]; then
            echo "ssd"
        else
            echo "hdd"
        fi
    else
        echo "unknown"
    fi
}


# Kernel Version Detection

get_latest_kernel_version() {
    local latest_stable=""
    local latest_lts_612=""
    local latest_lts_66=""

    # Fetch from kernel.org
    local kernel_page=$(wget -qO- https://www.kernel.org/ 2>/dev/null || curl -s https://www.kernel.org/ 2>/dev/null)

    if [[ -n "$kernel_page" ]]; then
        # Latest stable (mainline)
        latest_stable=$(echo "$kernel_page" | grep -oP 'mainline:.*?<strong>\K[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)

        # LTS versions
        latest_lts_612=$(echo "$kernel_page" | grep -oP '6\.12.*?<strong>\K6\.12\.[0-9]+' | head -1)
        latest_lts_66=$(echo "$kernel_page" | grep -oP '6\.6.*?<strong>\K6\.6\.[0-9]+' | head -1)

        # Fallback values
        [[ -z "$latest_stable" ]] && latest_stable="7.0"
        [[ -z "$latest_lts_612" ]] && latest_lts_612="6.12.15"
        [[ -z "$latest_lts_66" ]] && latest_lts_66="6.6.68"
    else
        latest_stable="7.0"
        latest_lts_612="6.12.15"
        latest_lts_66="6.6.68"
    fi

    echo "$latest_stable|$latest_lts_612|$latest_lts_66"
}


# Interactive Configuration

interactive_setup() {
    log_info "Universal Linux Kernel Builder with CachyOS Patches"
    echo ""

    # System info
    DISTRO=$(detect_distro)
    INIT_SYSTEM=$(detect_init_system)
    log_info "Detected distribution: $DISTRO (init: $INIT_SYSTEM)"
    echo ""

    # Check latest versions
    log_info "Checking latest kernel versions on kernel.org..."
    local versions=$(get_latest_kernel_version)
    IFS='|' read -r latest_stable latest_lts_612 latest_lts_66 <<< "$versions"
    echo ""

    # Version selection
    log_question "Install $latest_stable (latest available)?"
    echo "  1) Yes"
    echo "  2) Choose another version"
    read -p "Choice [1]: " kernel_choice
    kernel_choice=${kernel_choice:-1}

    if [[ "$kernel_choice" == "2" ]]; then
        echo ""
        log_question "Select kernel version:"
        echo "  1) $latest_stable (latest stable)"
        echo "  2) $latest_lts_612 (LTS)"
        echo "  3) $latest_lts_66 (LTS)"
        echo "  4) Enter manually"
        read -p "Choice: " alt_choice

        case $alt_choice in
            1)
                KERNEL_MAJOR=$(echo "$latest_stable" | cut -d. -f1)
                KERNEL_MINOR=$(echo "$latest_stable" | cut -d. -f2)
                KERNEL_PATCH=$(echo "$latest_stable" | cut -d. -f3)
                ;;
            2)
                KERNEL_MAJOR=$(echo "$latest_lts_612" | cut -d. -f1)
                KERNEL_MINOR=$(echo "$latest_lts_612" | cut -d. -f2)
                KERNEL_PATCH=$(echo "$latest_lts_612" | cut -d. -f3)
                ;;
            3)
                KERNEL_MAJOR=$(echo "$latest_lts_66" | cut -d. -f1)
                KERNEL_MINOR=$(echo "$latest_lts_66" | cut -d. -f2)
                KERNEL_PATCH=$(echo "$latest_lts_66" | cut -d. -f3)
                ;;
            4)
                read -p "Enter version (e.g., 7.0 or 6.19.12): " manual_version
                KERNEL_MAJOR=$(echo "$manual_version" | cut -d. -f1)
                KERNEL_MINOR=$(echo "$manual_version" | cut -d. -f2)
                KERNEL_PATCH=$(echo "$manual_version" | cut -d. -f3)
                ;;
            *)
                KERNEL_MAJOR=$(echo "$latest_stable" | cut -d. -f1)
                KERNEL_MINOR=$(echo "$latest_stable" | cut -d. -f2)
                KERNEL_PATCH=$(echo "$latest_stable" | cut -d. -f3)
                ;;
        esac
    else
        # Use latest
        KERNEL_MAJOR=$(echo "$latest_stable" | cut -d. -f1)
        KERNEL_MINOR=$(echo "$latest_stable" | cut -d. -f2)
        KERNEL_PATCH=$(echo "$latest_stable" | cut -d. -f3)
    fi

    if [[ -z "$KERNEL_PATCH" ]]; then
        KERNEL_VERSION="${KERNEL_MAJOR}.${KERNEL_MINOR}"
    else
        KERNEL_VERSION="${KERNEL_MAJOR}.${KERNEL_MINOR}.${KERNEL_PATCH}"
    fi
    log_success "Selected version: $KERNEL_VERSION"
    echo ""

    # CPU config
    read cores threads <<< $(detect_cpu_info)
    local detected_arch=$(detect_cpu_arch)

    log_question "CPU information:"
    echo "  Detected: $threads threads ($cores physical cores)"
    echo "  Microarchitecture: $detected_arch"
    read -p "Build threads [$threads]: " user_threads
    CPU_THREADS=${user_threads:-$threads}
    CPU_CORES=$cores

    log_question "Select CPU optimization:"
    echo "  1) $detected_arch (auto-detected, recommended)"
    echo "  2) GENERIC_CPU (universal, for any x86-64)"
    echo "  3) Enter manually"
    read -p "Choice [1]: " arch_choice
    arch_choice=${arch_choice:-1}

    case $arch_choice in
        1) CPU_ARCH="$detected_arch" ;;
        2) CPU_ARCH="GENERIC_CPU" ;;
        3)
            echo "Available: BROADWELL, SKYLAKE, COFFEELAKE, ALDERLAKE, RAPTORLAKE, ZEN, ZEN2, ZEN3, ZEN4, GENERIC_CPU"
            read -p "Enter architecture: " CPU_ARCH
            CPU_ARCH=$(echo "$CPU_ARCH" | tr '[:lower:]' '[:upper:]')
            ;;
    esac
    log_success "CPU: $CPU_ARCH ($CPU_THREADS threads)"
    echo ""

    # GPU config
    local detected_gpu=$(detect_gpu)
    log_question "Graphics card:"
    echo "  Detected: $detected_gpu"
    echo "  1) AMD (amdgpu)"
    echo "  2) NVIDIA (nouveau/proprietary)"
    echo "  3) Intel (i915/xe)"
    echo "  4) No GPU / other"
    read -p "Choice [auto-detect]: " gpu_choice

    case $gpu_choice in
        1) GPU_VENDOR="amd" ;;
        2) GPU_VENDOR="nvidia" ;;
        3) GPU_VENDOR="intel" ;;
        4) GPU_VENDOR="none" ;;
        *) GPU_VENDOR="$detected_gpu" ;;
    esac
    log_success "GPU: $GPU_VENDOR"
    echo ""

    # Storage config
    local detected_storage=$(detect_storage)
    log_question "Storage type:"
    echo "  Detected: $detected_storage"
    echo "  1) NVMe SSD"
    echo "  2) SATA SSD"
    echo "  3) HDD"
    read -p "Choice [auto-detect]: " storage_choice

    case $storage_choice in
        1) STORAGE_TYPE="nvme" ;;
        2) STORAGE_TYPE="ssd" ;;
        3) STORAGE_TYPE="hdd" ;;
        *) STORAGE_TYPE="$detected_storage" ;;
    esac
    log_success "Storage: $STORAGE_TYPE"
    echo ""

    # Confirm
    log_info "Final Configuration"
    echo "  Kernel: Linux $KERNEL_VERSION"
    echo "  CPU: $CPU_ARCH ($CPU_THREADS threads)"
    echo "  GPU: $GPU_VENDOR"
    echo "  Storage: $STORAGE_TYPE"
    echo "  Distribution: $DISTRO"
    echo ""
    read -p "Continue build? [Y/n]: " confirm
    confirm=${confirm:-Y}

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_error "Cancelled by user"
        exit 0
    fi
}


# Dependencies

check_dependencies() {
    log_info "Checking dependencies..."

    local deps=(
        "make" "gcc" "clang" "lld" "bc" "bison" "flex"
        "pahole" "perl" "wget" "patch" "xz" "zstd"
    )

    local missing=()
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing[*]}"
        log_info "Install them for your distribution:"

        case "$DISTRO" in
            void)
                echo "sudo xbps-install -S base-devel ncurses-devel openssl-devel elfutils-devel bc pahole flex bison perl zstd xz wget patch clang lld llvm"
                ;;
            arch|manjaro)
                echo "sudo pacman -S base-devel bc pahole flex bison perl zstd xz wget patch clang lld llvm"
                ;;
            debian|ubuntu)
                echo "sudo apt install build-essential bc pahole flex bison libelf-dev libssl-dev libncurses-dev perl zstd xz-utils wget patch clang lld llvm"
                ;;
            fedora)
                echo "sudo dnf install @development-tools bc dwarves flex bison elfutils-libelf-devel openssl-devel ncurses-devel perl zstd xz wget patch clang lld llvm"
                ;;
            *)
                echo "Install: build tools, bc, pahole, flex, bison, elfutils, openssl, ncurses, perl, zstd, xz, wget, patch, clang, lld, llvm"
                ;;
        esac
        exit 1
    fi

    log_success "All dependencies installed"
}


# Download

download_kernel() {
    log_info "Downloading Linux kernel $KERNEL_VERSION..."

    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"

    local kernel_url="https://cdn.kernel.org/pub/linux/kernel/v${KERNEL_MAJOR}.x/linux-${KERNEL_VERSION}.tar.xz"
    local kernel_file="linux-${KERNEL_VERSION}.tar.xz"

    if [[ ! -f "$kernel_file" ]]; then
        wget -c "$kernel_url" -O "$kernel_file" || {
            log_error "Failed to download kernel"
            exit 1
        }
    fi

    if [[ ! -d "linux-${KERNEL_VERSION}" ]]; then
        log_info "Extracting kernel..."
        tar -xf "$kernel_file"
    fi

    log_success "Kernel downloaded"
}

download_cachyos_patches() {
    log_info "Downloading CachyOS patches..."

    local patches_dir="${BUILD_DIR}/patches-${KERNEL_VERSION}"
    mkdir -p "$patches_dir"
    cd "$patches_dir"

    local base_url="https://raw.githubusercontent.com/CachyOS/kernel-patches/master/${KERNEL_MAJOR}.${KERNEL_MINOR}"

    # CachyOS patches
    local patches=(
        "sched/0001-bore-cachy.patch"
        "misc/0001-cgroup-vram.patch"
    )

    # 6.x compatibility
    if [[ "${KERNEL_MAJOR}" -lt 7 ]]; then
        patches+=("all/0001-cachyos-base-all.patch")
    fi

    for patch in "${patches[@]}"; do
        local patch_name=$(basename "$patch")
        if [[ ! -f "$patch_name" ]]; then
            local url="${base_url}/${patch}"
            if wget -q --spider "$url" 2>/dev/null; then
                wget -c "$url" -O "$patch_name" || log_warn "Skipping $patch_name"
            else
                log_warn "Patch $patch_name unavailable for version ${KERNEL_MAJOR}.${KERNEL_MINOR}"
            fi
        fi
    done

    log_success "Patches downloaded"
}

apply_patches() {
    log_info "Applying patches..."

    local kernel_src="${BUILD_DIR}/linux-${KERNEL_VERSION}"
    local patches_dir="${BUILD_DIR}/patches-${KERNEL_VERSION}"

    cd "$kernel_src"

    for patch in "$patches_dir"/*.patch; do
        if [[ -f "$patch" ]]; then
            local patch_name=$(basename "$patch")
            log_info "Applying: $patch_name"

            if patch -p1 --dry-run -N -i "$patch" &>/dev/null; then
                patch -p1 -N -i "$patch"
                log_success "$patch_name applied"
            else
                log_warn "$patch_name skipped (already applied or conflict)"
            fi
        fi
    done

    log_success "Patches applied"
}


# Configuration

configure_kernel() {
    log_info "Configuring kernel..."

    local kernel_src="${BUILD_DIR}/linux-${KERNEL_VERSION}"
    cd "$kernel_src"

    # Base config
    if [[ -f /proc/config.gz ]]; then
        zcat /proc/config.gz > .config
    elif [[ -f "/boot/config-$(uname -r)" ]]; then
        cp "/boot/config-$(uname -r)" .config
    else
        make LLVM=1 defconfig
    fi

    # CPU
    ./scripts/config --enable CONFIG_M${CPU_ARCH}
    ./scripts/config --set-val CONFIG_NR_CPUS $((CPU_THREADS > 512 ? 512 : CPU_THREADS))

    # Scheduler
    ./scripts/config --enable CONFIG_SCHED_BORE || true
    ./scripts/config --enable CONFIG_PREEMPT
    ./scripts/config --disable CONFIG_PREEMPT_VOLUNTARY
    ./scripts/config --disable CONFIG_PREEMPT_NONE
    ./scripts/config --set-val CONFIG_HZ 1000
    ./scripts/config --enable CONFIG_HZ_1000

    # GPU config drivers
    case "$GPU_VENDOR" in
        amd)
            ./scripts/config --enable CONFIG_DRM_AMDGPU
            ./scripts/config --enable CONFIG_DRM_AMDGPU_SI
            ./scripts/config --enable CONFIG_DRM_AMDGPU_CIK
            ./scripts/config --enable CONFIG_DRM_AMD_DC
            ./scripts/config --enable CONFIG_HSA_AMD
            ;;
        nvidia)
            ./scripts/config --enable CONFIG_DRM_NOUVEAU
            ;;
        intel)
            ./scripts/config --enable CONFIG_DRM_I915
            ./scripts/config --enable CONFIG_DRM_XE
            ;;
    esac

    # Storage config
    case "$STORAGE_TYPE" in
        nvme)
            ./scripts/config --enable CONFIG_BLK_DEV_NVME
            ./scripts/config --set-str CONFIG_DEFAULT_IOSCHED "none"
            ;;
        ssd)
            ./scripts/config --enable CONFIG_MQ_IOSCHED_DEADLINE
            ./scripts/config --set-str CONFIG_DEFAULT_IOSCHED "mq-deadline"
            ;;
        hdd)
            ./scripts/config --enable CONFIG_IOSCHED_BFQ
            ./scripts/config --set-str CONFIG_DEFAULT_IOSCHED "bfq"
            ;;
    esac

    # Memory
    ./scripts/config --enable CONFIG_TRANSPARENT_HUGEPAGE_MADVISE
    ./scripts/config --enable CONFIG_LRU_GEN
    ./scripts/config --enable CONFIG_LRU_GEN_ENABLED
    ./scripts/config --enable CONFIG_ZSWAP
    ./scripts/config --enable CONFIG_ZRAM
    ./scripts/config --set-str CONFIG_ZSWAP_COMPRESSOR_DEFAULT "zstd"

    # Network
    ./scripts/config --enable CONFIG_TCP_CONG_BBR
    ./scripts/config --set-str CONFIG_DEFAULT_TCP_CONG "bbr"

    # Compiler
    ./scripts/config --enable CONFIG_LTO_CLANG_THIN
    ./scripts/config --enable CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE

    # Gaming
    ./scripts/config --enable CONFIG_FUTEX
    ./scripts/config --enable CONFIG_FUTEX2
    ./scripts/config --enable CONFIG_NTSYNC || true

    # Containers
    ./scripts/config --enable CONFIG_NAMESPACES
    ./scripts/config --enable CONFIG_CGROUPS
    ./scripts/config --enable CONFIG_MEMCG

    # Debug
    ./scripts/config --disable CONFIG_DEBUG_INFO
    ./scripts/config --disable CONFIG_DEBUG_INFO_BTF

    # Name
    ./scripts/config --set-str CONFIG_LOCALVERSION "-bore"
    ./scripts/config --disable CONFIG_LOCALVERSION_AUTO

    # Finalize
    make LLVM=1 olddefconfig

    log_success "Configuration complete"
}


# Build

compile_kernel() {
    log_info "Compiling kernel (this will take 20-90 minutes)..."

    local kernel_src="${BUILD_DIR}/linux-${KERNEL_VERSION}"
    cd "$kernel_src"

    make LLVM=1 -j"$CPU_THREADS" || {
        log_error "Compilation failed"
        exit 1
    }

    log_success "Compilation complete"
}


# Install

install_kernel() {
    log_info "Installing kernel..."

    if [[ $EUID -ne 0 ]]; then
        log_error "Root privileges required for installation"
        exit 1
    fi

    # Auto-detect version
    if [[ -z "$KERNEL_VERSION" ]]; then
        local kernel_dir=$(ls -d "${BUILD_DIR}"/linux-* 2>/dev/null | head -1)
        if [[ -z "$kernel_dir" ]]; then
            log_error "No kernel found in build directory. Run build first."
            exit 1
        fi
        KERNEL_VERSION=$(basename "$kernel_dir" | sed 's/^linux-//')
        log_info "Detected kernel version: $KERNEL_VERSION"
    fi

    # Detect distro
    if [[ -z "$DISTRO" ]]; then
        DISTRO=$(detect_distro)
    fi

    local kernel_src="${BUILD_DIR}/linux-${KERNEL_VERSION}"
    cd "$kernel_src"

    # Install modules
    log_info "Installing modules..."
    make LLVM=1 modules_install

    # Detect module directory
    local module_dir=$(ls -d /lib/modules/${KERNEL_VERSION}* 2>/dev/null | sort -V | tail -1)
    if [[ -z "$module_dir" ]]; then
        log_error "Module directory not found after installation"
        exit 1
    fi
    local kernel_release=$(basename "$module_dir")
    log_info "Module directory: $kernel_release"

    # Install kernel files
    log_info "Installing kernel..."
    cp -v arch/x86/boot/bzImage "/boot/vmlinuz-${kernel_release}"
    cp -v System.map "/boot/System.map-${kernel_release}"
    cp -v .config "/boot/config-${kernel_release}"

    # Generate initramfs
    log_info "Generating initramfs..."
    case "$DISTRO" in
        void|arch|manjaro)
            if command -v dracut &>/dev/null; then
                dracut --force --hostonly --kver "$kernel_release" "/boot/initramfs-${kernel_release}.img"
            elif command -v mkinitcpio &>/dev/null; then
                mkinitcpio -k "$kernel_release" -g "/boot/initramfs-${kernel_release}.img"
            fi
            ;;
        debian|ubuntu)
            update-initramfs -c -k "$kernel_release"
            ;;
        fedora)
            dracut --force --kver "$kernel_release" "/boot/initramfs-${kernel_release}.img"
            ;;
    esac

    log_success "Kernel installed: $kernel_release"
    log_warn "Don't forget to update your bootloader (GRUB/systemd-boot/rEFInd)"
    log_info "Reboot your system to use the new kernel"
}


# Cleanup

clean_build() {
    log_info "Cleaning build directory..."
    rm -rf "$BUILD_DIR"
    log_success "Cleanup complete"
}


# Main

main() {
    case "${1:-}" in
        clean)
            clean_build
            ;;
        install)
            install_kernel
            ;;
        *)
            interactive_setup
            check_dependencies
            download_kernel
            download_cachyos_patches
            apply_patches
            configure_kernel
            compile_kernel

            log_success "Build complete"
            log_info "To install, run: sudo $0 install"
            ;;
    esac
}

main "$@"
