# Clerestory (Bash) 🏛️

> **Zero-Dependency, Pure Bash Implementation of the Hardware-Adaptive Windows 11 KVM Optimizer**

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  CLERESTORY (BASH)   Hardware-Adaptive Windows 11 KVM Optimizer             │
├─────────────────────────────────────────────────────────────────────────────┤
│  • Single-CCD & P-Core Cache-Aware Pinning Discovery                        │
│  • All 12 Hyper-V Enlightenments + Invariant Sub-Microsecond TSC            │
│  • VirtIO-SCSI with io_uring, cache=none, and TRIM Thin-Provisioning       │
│  • Automated FAT32 OEMDRV & autounattend.xml Slipstream                     │
│  • Supports Spice, Looking Glass, VFIO Passthrough & Intel GVT-g            │
│  • Zero compiler / runtime dependencies — Runs on pure POSIX Bash!          │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## ⚡ Quick Start

```bash
# 1. Run live hardware diagnostics
./clerestory.sh doctor

# 2. Provision optimized Windows 11 VM in one command
./clerestory.sh create \
  --name "win11-1" \
  --ram 6144 \
  --disk 30 \
  --disk-path ~/containers/VMs/win11-1 \
  --iso /path/to/Win11_English_x64.iso \
  --username "ritesh" \
  --gpu-mode spice

# 3. Dry-run synthesis (view generated XML without writing files)
./clerestory.sh create --name "win11-dry" --iso /dev/null --dry-run
```

---

## 🏗️ Architecture & Modules

* **`clerestory.sh`**: Master CLI entrypoint with subcommands (`doctor`, `create`, `inspect`, `list`, `start`, `stop`, `destroy`, `completions`).
* **`lib/probe.sh`**: Inspects `/sys/devices/system/cpu/`, L3 cache domains, SMT thread pairs, NUMA, hugepages, `io_uring`, TRIM, `swtpm`, and `OVMF` SecureBoot paths.
* **`lib/optimizer.sh`**: Computes single-CCD core locking, Intel P-core isolation, and host housekeeping pinouts (`emulatorpin`, `iothreadpin`).
* **`lib/xml.sh`**: Synthesizes 100% schema-compliant Libvirt Domain XML.
* **`lib/slipstream.sh`**: Synthesizes Microsoft `autounattend.xml` answer file and formats virtual FAT32 `OEMDRV` disk volume.
* **`lib/qemu.sh`**: Synthesizes self-contained standalone QEMU bash runner scripts.
* **`tests/test_clerestory.sh`**: Automated validation test suite.

---

## 🧪 Running Automated Tests

```bash
./tests/test_clerestory.sh
```

---

## 📄 License

Dual-licensed under MIT or Apache-2.0.
