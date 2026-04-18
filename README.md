# BORE Kernel Builder

Universal Linux kernel builder with [CachyOS](https://github.com/CachyOS/kernel-patches) patches and BORE (Burst-Oriented Response Enhancer) scheduler.

## Features

- **Automatic hardware detection** - CPU architecture, GPU vendor, storage type
- **Auto-fetches latest kernel versions** from kernel.org
- **Optimized for your hardware** - Intel/AMD CPU optimizations, GPU drivers, I/O schedulers
- **Multi-distro support** - Void, Arch, Debian, Ubuntu, Fedora
- **BORE scheduler** - Improved system responsiveness under load
- **Clang + ThinLTO** - Fast compilation with link-time optimization
- **Gaming optimizations** - FUTEX2, NTSYNC for Wine/Proton

## Quick Start

```bash
# 1. Clone repository
git clone https://github.com/prostitutionofthesoul/bore-kernel-builder.git
cd bore-kernel-builder

# 2. Install dependencies (see Requirements section below)

# 3. Build kernel
./bore-kernel-builder.sh

# 4. Install kernel
sudo ./bore-kernel-builder.sh install

# 5. Update bootloader (see Bootloader Configuration section)

# 6. Reboot
sudo reboot
```

## Requirements

### Void Linux
```bash
sudo xbps-install -S base-devel ncurses-devel openssl-devel elfutils-devel \
    bc pahole flex bison perl zstd xz wget patch clang lld llvm dracut
```

### Arch Linux / Manjaro
```bash
sudo pacman -S base-devel bc pahole flex bison perl zstd xz wget patch clang lld llvm
```

### Debian / Ubuntu
```bash
sudo apt update
sudo apt install build-essential bc pahole flex bison libelf-dev libssl-dev \
    libncurses-dev perl zstd xz-utils wget patch clang lld llvm
```

### Fedora
```bash
sudo dnf install @development-tools bc dwarves flex bison elfutils-libelf-devel \
    openssl-devel ncurses-devel perl zstd xz wget patch clang lld llvm
```

## Usage

### Interactive Build

Run the script and follow the prompts:

```bash
./bore-kernel-builder.sh
```

The script will:
1. **Check latest kernel versions** on kernel.org
2. **Ask which version to install** (latest stable, LTS, or manual entry)
3. **Auto-detect your hardware**:
   - CPU architecture (Intel Haswell→Raptor Lake, AMD Zen→Zen4)
   - GPU vendor (AMD, NVIDIA, Intel)
   - Storage type (NVMe, SATA SSD, HDD)
4. **Download kernel source** and CachyOS patches
5. **Configure kernel** with ~200 optimizations
6. **Compile** (40-200 minutes depending on CPU)

### Install Kernel

After successful build:

```bash
sudo ./bore-kernel-builder.sh install
```

This will:
- Install kernel to `/boot/vmlinuz-{VERSION}-bore`
- Install modules to `/lib/modules/{VERSION}-bore/`
- Generate initramfs
- Copy System.map and .config

### Clean Build Directory

Remove build directory (~20GB):

```bash
./bore-kernel-builder.sh clean
```

## Bootloader Configuration

After installation, you **must** update your bootloader before rebooting.

### GRUB

```bash
sudo grub-mkconfig -o /boot/grub/grub.cfg
sudo reboot
```

### systemd-boot

Edit or create boot entry in `/boot/loader/entries/`:

```bash
sudo nano /boot/loader/entries/linux-bore.conf
```

Example entry:
```
title   Linux BORE
linux   /vmlinuz-7.0-bore
initrd  /initramfs-7.0-bore.img
options root=UUID=YOUR-ROOT-UUID rw quiet
```

Find your root UUID:
```bash
lsblk -f
```

Then update and reboot:
```bash
sudo bootctl update
sudo reboot
```
### rEFInd

rEFInd auto-detects kernels in `/boot/`. Just reboot:

```bash
sudo reboot
```

### EFI Stub

If you boot directly via UEFI without a bootloader:

```bash
# Find your root UUID
ROOT_UUID=$(lsblk -f | grep "/$" | awk '{print $4}')

# Create EFI boot entry
sudo efibootmgr --create \
    --disk /dev/sda \
    --part 1 \
    --label "Linux BORE" \
    --loader /vmlinuz-7.0-bore \
    --unicode "root=UUID=${ROOT_UUID} rw initrd=\\initramfs-7.0-bore.img"

sudo reboot
```

**Note**: Adjust `/dev/sda` and partition number (`--part 1`) to match your EFI partition.

## Kernel Features

### BORE Scheduler
Burst-Oriented Response Enhancer - improves system responsiveness under load, especially for interactive workloads and gaming.

### CPU Optimizations
- **Intel**: Haswell, Broadwell, Skylake, Coffee Lake, Comet Lake, Tiger Lake, Alder Lake, Raptor Lake
- **AMD**: Zen, Zen2, Zen3, Zen4
- **Generic**: GENERIC_CPU for universal x86-64 compatibility

### Performance Features
- **Preemption**: Full preemption (`CONFIG_PREEMPT=y`) for low latency
- **Timer**: 1000 Hz for better responsiveness
- **Compiler**: Clang with ThinLTO and -O3 optimization
- **Memory**: Multi-Gen LRU, THP on demand, ZSWAP with zstd compression
- **Network**: BBR congestion control

### Gaming Features
- **FUTEX2**: Improved futex implementation for better Wine/Proton performance
- **NTSYNC**: Windows synchronization primitives for gaming

### GPU Support
- **AMD**: amdgpu driver (RX 5000/6000/7000 series, legacy SI/CIK support)
- **NVIDIA**: nouveau driver (open-source)
- **Intel**: i915 and xe drivers

### Storage Optimizations
- **NVMe**: No I/O scheduler (best for NVMe)
- **SATA SSD**: mq-deadline scheduler
- **HDD**: BFQ scheduler

### Container Support
- Full Docker/Podman support (namespaces, cgroups, memory cgroups)

## Build Time

Compilation time depends on your CPU:

- **20 threads**: ~40 minutes
- **16 threads**: ~50 minutes
- **8 threads**: ~100 minutes
- **4 threads**: ~200 minutes

## Disk Space

- **During build**: ~20 GB
- **After installation**: ~500 MB (kernel + modules)
- **Tip**: Run `./bore-kernel-builder.sh clean` after installation to free up space

## Advanced Usage

### Manual Kernel Version

If you want a specific kernel version not listed:

```bash
./bore-kernel-builder.sh
# Select option 2 (Choose another version)
# Select option 4 (Enter manually)
# Enter version: 6.19.12
```

### Custom CPU Architecture

If auto-detection fails or you want a different optimization:

```bash
./bore-kernel-builder.sh
# When prompted for CPU optimization, select option 3 (Enter manually)
# Available: BROADWELL, SKYLAKE, COFFEELAKE, ALDERLAKE, RAPTORLAKE, 
#            ZEN, ZEN2, ZEN3, ZEN4, GENERIC_CPU
```

### Build for Different Hardware

You can override auto-detection during interactive setup:

- **CPU**: Choose different architecture optimization
- **GPU**: Select different GPU vendor
- **Storage**: Select different storage type

## Updating Kernel

To update to a newer kernel version:

```bash
# Clean old build
./bore-kernel-builder.sh clean

# Build new version
./bore-kernel-builder.sh
# Select new version when prompted

# Install
sudo ./bore-kernel-builder.sh install

# Update bootloader
sudo grub-mkconfig -o /boot/grub/grub.cfg  # or your bootloader

# Reboot
sudo reboot
```

## Uninstalling

To remove a kernel:

```bash
# Remove kernel files
sudo rm /boot/vmlinuz-7.0-bore
sudo rm /boot/initramfs-7.0-bore.img
sudo rm /boot/System.map-7.0-bore
sudo rm /boot/config-7.0-bore

# Remove modules
sudo rm -rf /lib/modules/7.0-bore

# Update bootloader
sudo grub-mkconfig -o /boot/grub/grub.cfg  # or your bootloader
```

## Credits

- [CachyOS](https://github.com/CachyOS/kernel-patches) - BORE scheduler and kernel patches
- [Linux Kernel](https://kernel.org/) - The Linux kernel

## License

This script is provided as-is under the MIT License. The Linux kernel is licensed under GPL-2.0.
