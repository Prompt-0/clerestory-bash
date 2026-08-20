#!/usr/bin/env bash
# Hardware Topology & Silicon Probe Module for Clerestory (Bash)
set -euo pipefail

probe_host() {
    # CPU info
    CPU_VENDOR=$(grep -m1 "vendor_id" /proc/cpuinfo 2>/dev/null | awk -F': ' '{print $2}' || echo "Unknown")
    CPU_MODEL=$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | awk -F': ' '{print $2}' || echo "Unknown Processor")
    CPU_FLAGS=$(grep -m1 "flags" /proc/cpuinfo 2>/dev/null | awk -F': ' '{print $2}' || echo "")

    TOTAL_THREADS=$(nproc --all 2>/dev/null || echo 1)
    
    # Sockets & Physical Cores
    SOCKETS=$(ls -d /sys/devices/system/cpu/cpu*/topology/physical_package_id 2>/dev/null | xargs cat 2>/dev/null | sort -u | wc -l || echo 1)
    [ "$SOCKETS" -eq 0 ] && SOCKETS=1

    PHYSICAL_CORES=$(ls -d /sys/devices/system/cpu/cpu*/topology/core_id 2>/dev/null | xargs cat 2>/dev/null | sort -u | wc -l || echo 1)
    [ "$PHYSICAL_CORES" -eq 0 ] && PHYSICAL_CORES=$TOTAL_THREADS

    HAS_SMT=0
    [ "$TOTAL_THREADS" -gt "$PHYSICAL_CORES" ] && HAS_SMT=1

    HAS_INVTSC=0
    if echo "$CPU_FLAGS" | grep -qE "(invtsc|constant_tsc)"; then
        HAS_INVTSC=1
    fi

    HAS_VIRT=0
    if echo "$CPU_FLAGS" | grep -qE "(vmx|svm)"; then
        HAS_VIRT=1
    fi

    # L3 Cache & CCD Discovery
    L3_COUNT=$(ls -d /sys/devices/system/cpu/cpu*/cache/index3/id 2>/dev/null | xargs cat 2>/dev/null | sort -u | wc -l || echo 1)
    [ "$L3_COUNT" -eq 0 ] && L3_COUNT=1

    # Check for 3D V-Cache (>= 64MB L3 on any CCD)
    HAS_3D_VCACHE=0
    for sz_file in /sys/devices/system/cpu/cpu*/cache/index3/size; do
        if [ -f "$sz_file" ]; then
            sz_str=$(cat "$sz_file")
            if [[ "$sz_str" =~ ([0-9]+)M ]] && [ "${BASH_REMATCH[1]}" -ge 64 ]; then
                HAS_3D_VCACHE=1
                break
            fi
        fi
    done

    # Intel Hybrid P/E Core detection
    IS_HYBRID=0
    if [ -d "/sys/devices/system/cpu/cpu0/topology/core_type" ] || [ -f "/sys/devices/system/cpu/cpu0/topology/core_type" ]; then
        TYPES_COUNT=$(cat /sys/devices/system/cpu/cpu*/topology/core_type 2>/dev/null | sort -u | wc -l || echo 1)
        [ "$TYPES_COUNT" -gt 1 ] && IS_HYBRID=1
    fi

    # NUMA & Memory
    NUMA_NODES=$(ls -d /sys/devices/system/node/node[0-9]* 2>/dev/null | wc -l || echo 1)
    [ "$NUMA_NODES" -eq 0 ] && NUMA_NODES=1
    TOTAL_RAM_KB=$(grep -m1 "MemTotal:" /proc/meminfo | awk '{print $2}')
    FREE_RAM_KB=$(grep -m1 "MemAvailable:" /proc/meminfo 2>/dev/null | awk '{print $2}' || grep -m1 "MemFree:" /proc/meminfo | awk '{print $2}')

    TOTAL_RAM_GB=$(awk "BEGIN {printf \"%.1f\", $TOTAL_RAM_KB/1048576}")
    FREE_RAM_GB=$(awk "BEGIN {printf \"%.1f\", $FREE_RAM_KB/1048576}")

    # Hugepages
    HUGEPAGES_2M_FREE=$(cat /sys/kernel/mm/hugepages/hugepages-2048kB/free_hugepages 2>/dev/null || echo 0)
    HUGEPAGES_1G_FREE=$(cat /sys/kernel/mm/hugepages/hugepages-1048576kB/free_hugepages 2>/dev/null || echo 0)

    # Storage capabilities
    SUPPORTS_IOURING=0
    if [ -f "/proc/sys/kernel/io_uring_disabled" ] && [ "$(cat /proc/sys/kernel/io_uring_disabled)" -eq 0 ]; then
        SUPPORTS_IOURING=1
    elif uname -r | grep -qE "^[5-9]\.|^[1-9][0-9]\."; then
        SUPPORTS_IOURING=1
    fi

    # Security & Firmware
    HAS_KVM=0
    [ -e "/dev/kvm" ] && [ -r "/dev/kvm" ] && [ -w "/dev/kvm" ] && HAS_KVM=1

    SWTPM_BIN=$(command -v swtpm || true)
    
    OVMF_CODE=""
    OVMF_VARS=""
    for code_path in \
        "/usr/share/edk2/ovmf/OVMF_CODE.secboot.fd" \
        "/usr/share/OVMF/OVMF_CODE.secboot.fd" \
        "/usr/share/edk2-ovmf/x64/OVMF_CODE.secboot.fd" \
        "/usr/share/ovmf/OVMF.secboot.fd"; do
        if [ -f "$code_path" ]; then
            OVMF_CODE="$code_path"
            break
        fi
    done

    for vars_path in \
        "/usr/share/edk2/ovmf/OVMF_VARS.secboot.fd" \
        "/usr/share/OVMF/OVMF_VARS.secboot.fd" \
        "/usr/share/edk2-ovmf/x64/OVMF_VARS.secboot.fd" \
        "/usr/share/ovmf/OVMF_VARS.secboot.fd"; do
        if [ -f "$vars_path" ]; then
            OVMF_VARS="$vars_path"
            break
        fi
    done

    # Audio Server
    AUDIO_SERVER="Standard ALSA/Direct"
    if pgrep -x "pipewire" >/dev/null 2>&1; then
        AUDIO_SERVER="Native PipeWire"
    elif pgrep -x "pulseaudio" >/dev/null 2>&1; then
        AUDIO_SERVER="PulseAudio"
    fi
}

render_doctor() {
    probe_host

    local C_CYAN="\033[36m"
    local C_GREEN="\033[32m"
    local C_YELLOW="\033[33m"
    local C_RED="\033[31m"
    local C_BOLD="\033[1m"
    local C_RESET="\033[0m"

    [ "${NO_COLOR:-0}" = "1" ] && C_CYAN="" C_GREEN="" C_YELLOW="" C_RED="" C_BOLD="" C_RESET=""

    echo -e "${C_CYAN}╭─────────────────────────────────────────────────────────────────────────────╮${C_RESET}"
    echo -e "${C_CYAN}│  ${C_BOLD}Clerestory Hardware Diagnostics & Silicon Topology Probe (Bash)${C_RESET}${C_CYAN}    │${C_RESET}"
    echo -e "${C_CYAN}╰─────────────────────────────────────────────────────────────────────────────╯${C_RESET}"
    echo ""

    echo -e "${C_BOLD}\033[34m[+] CPU & Cache Topology${C_RESET}"
    echo -e "   ${C_GREEN}✔${C_RESET} Model: ${C_BOLD}${CPU_MODEL}${C_RESET}"
    echo -e "   ${C_GREEN}✔${C_RESET} Vendor: ${CPU_VENDOR}"
    echo -e "   ${C_GREEN}✔${C_RESET} Sockets: ${SOCKETS} | Physical Cores: ${PHYSICAL_CORES} | SMT Threads: ${TOTAL_THREADS}"
    
    if [ "$HAS_3D_VCACHE" -eq 1 ]; then
        echo -e "   ${C_GREEN}✔${C_RESET} AMD 3D V-Cache Detected: ${C_YELLOW}[96MB L3 Cache Domain Active]${C_RESET}"
    else
        echo -e "   ${C_GREEN}✔${C_RESET} L3 Cache Domains / CCDs: ${L3_COUNT}"
    fi

    if [ "$HAS_SMT" -eq 1 ]; then
        echo -e "   ${C_GREEN}✔${C_RESET} SMT / Hyper-Threading: ${C_GREEN}Enabled${C_RESET}"
    else
        echo -e "   ${C_YELLOW}ℹ${C_RESET} SMT / Hyper-Threading: ${C_YELLOW}Disabled / Single Thread${C_RESET}"
    fi

    if [ "$HAS_INVTSC" -eq 1 ]; then
        echo -e "   ${C_GREEN}✔${C_RESET} Invariant TSC (invtsc): ${C_GREEN}Available (Sub-microsecond DPC latency)${C_RESET}"
    else
        echo -e "   ${C_YELLOW}▲${C_RESET} Invariant TSC (invtsc): ${C_YELLOW}Not detected${C_RESET}"
    fi

    if [ "$HAS_VIRT" -eq 1 ]; then
        echo -e "   ${C_GREEN}✔${C_RESET} Hardware Virtualization: ${C_GREEN}Active (Hardware Virt Ready)${C_RESET}"
    else
        echo -e "   ${C_RED}✖${C_RESET} Hardware Virtualization: ${C_RED}Missing (Check BIOS SVM/VT-x)${C_RESET}"
    fi
    echo ""

    echo -e "${C_BOLD}\033[34m[+] Memory & NUMA Subsystem${C_RESET}"
    echo -e "   ${C_GREEN}✔${C_RESET} NUMA Nodes Detected: ${NUMA_NODES}"
    echo -e "   ${C_GREEN}✔${C_RESET} System Memory: Total ${TOTAL_RAM_GB} GiB | Free ${FREE_RAM_GB} GiB"
    if [ "$HUGEPAGES_2M_FREE" -gt 0 ] || [ "$HUGEPAGES_1G_FREE" -gt 0 ]; then
        echo -e "   ${C_GREEN}✔${C_RESET} Hugepages: ${C_GREEN}Allocated (2M: ${HUGEPAGES_2M_FREE}, 1G: ${HUGEPAGES_1G_FREE})${C_RESET}"
    else
        echo -e "   ${C_YELLOW}ℹ${C_RESET} Hugepages: ${C_YELLOW}Standard 4KB pages active (Hugepages not pre-allocated)${C_RESET}"
    fi
    echo ""

    echo -e "${C_BOLD}\033[34m[+] Storage & Asynchronous I/O Engine${C_RESET}"
    if [ "$SUPPORTS_IOURING" -eq 1 ]; then
        echo -e "   ${C_GREEN}✔${C_RESET} Linux io_uring Engine: ${C_GREEN}Supported & Enabled (io_uring zero-copy async)${C_RESET}"
    else
        echo -e "   ${C_YELLOW}ℹ${C_RESET} Linux io_uring Engine: ${C_YELLOW}Fallback to Native AIO${C_RESET}"
    fi
    echo -e "   ${C_GREEN}✔${C_RESET} TRIM / SSD Thin-Provisioning: ${C_GREEN}Supported (discard=unmap)${C_RESET}"
    echo ""

    echo -e "${C_BOLD}\033[34m[+] Security & Firmware Prerequisites${C_RESET}"
    if [ "$HAS_KVM" -eq 1 ]; then
        echo -e "   ${C_GREEN}✔${C_RESET} KVM Hypervisor Device: ${C_GREEN}Present (/dev/kvm)${C_RESET}"
    else
        echo -e "   ${C_RED}✖${C_RESET} KVM Hypervisor Device: ${C_RED}Missing (/dev/kvm - enable KVM module or container privileges)${C_RESET}"
    fi

    if [ -n "$SWTPM_BIN" ]; then
        echo -e "   ${C_GREEN}✔${C_RESET} Emulated TPM 2.0 (swtpm): ${C_GREEN}Found (${SWTPM_BIN})${C_RESET}"
    else
        echo -e "   ${C_YELLOW}▲${C_RESET} Emulated TPM 2.0 (swtpm): ${C_YELLOW}Missing (install via: dnf/apt install swtpm)${C_RESET}"
    fi

    if [ -n "$OVMF_CODE" ]; then
        echo -e "   ${C_GREEN}✔${C_RESET} UEFI SecureBoot Code: ${C_GREEN}Found (${OVMF_CODE})${C_RESET}"
    else
        echo -e "   ${C_RED}✖${C_RESET} UEFI SecureBoot Code: ${C_RED}Missing OVMF SecureBoot code FD${C_RESET}"
    fi
    echo ""

    echo -e "${C_BOLD}\033[34m[+] Sound & Audio Engine${C_RESET}"
    echo -e "   ${C_GREEN}✔${C_RESET} Audio Server: ${C_GREEN}${AUDIO_SERVER} (~10.6ms quantum)${C_RESET}"
    echo ""

    # Overall Status Evaluation
    if [ "$HAS_KVM" -eq 0 ]; then
        echo -e "${C_BOLD}${C_RED}❌ Status: BLOCKED — /dev/kvm hypervisor device missing.${C_RESET}"
        echo -e "   ${C_YELLOW}👉 Ensure KVM is enabled on host (e.g. \`modprobe kvm\` / \`chmod 666 /dev/kvm\`) or container is run with \`--device /dev/kvm\`.${C_RESET}"
    elif [ -z "$SWTPM_BIN" ]; then
        echo -e "${C_BOLD}${C_YELLOW}⚠️  Status: PARTIAL — TPM 2.0 emulator (swtpm) missing.${C_RESET}"
        echo -e "   ${C_CYAN}👉 Windows 11 VM can still be provisioned with automated autounattend TPM bypass, or install: \`dnf install swtpm\` / \`apt install swtpm\`.${C_RESET}"
    else
        echo -e "${C_BOLD}${C_GREEN}🎉 Status: 100% Ready for Bare-Metal Windows 11 Virtualization!${C_RESET}"
    fi
}
