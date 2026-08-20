#!/usr/bin/env bash
# CPU Pinning & Topology Optimization Module for Clerestory (Bash)
set -euo pipefail

calculate_cpu_pinning() {
    local requested_vcpus="$1"
    local total_threads="$2"
    local has_smt="$3"
    local is_hybrid="$4"

    VCPU_PINS=()
    EMULATOR_PINS=()
    IOTHREAD_PINS=()

    # Discover CPU thread pairs from sysfs
    local allocated=()
    local vcpu=0

    # Collect CPU IDs from first CCD or online CPUs
    local cpus_to_use=()
    if [ -d "/sys/devices/system/cpu/cpu0/cache/index3" ]; then
        # Group by first L3 cache domain if available
        local first_l3_id=$(cat /sys/devices/system/cpu/cpu0/cache/index3/id 2>/dev/null || echo 0)
        for cpu_dir in /sys/devices/system/cpu/cpu[0-9]*; do
            local cid=$(basename "$cpu_dir" | sed 's/cpu//')
            local l3_id=$(cat "$cpu_dir/cache/index3/id" 2>/dev/null || echo 0)
            if [ "$l3_id" = "$first_l3_id" ]; then
                cpus_to_use+=("$cid")
            fi
        done
    fi

    # Fallback to standard online CPU list if discovery failed
    if [ "${#cpus_to_use[@]}" -eq 0 ]; then
        for ((i=0; i<total_threads; i++)); do
            cpus_to_use+=("$i")
        done
    fi

    # Allocate requested vCPUs
    for cid in "${cpus_to_use[@]}"; do
        if [ "$vcpu" -lt "$requested_vcpus" ]; then
            VCPU_PINS+=("$vcpu:$cid")
            allocated+=("$cid")
            vcpu=$((vcpu + 1))
        fi
    done

    # Find unallocated CPUs for emulatorpin and iothreadpin
    local unallocated=()
    for ((i=0; i<total_threads; i++)); do
        local is_alloc=0
        for a in "${allocated[@]}"; do
            if [ "$i" -eq "$a" ]; then
                is_alloc=1
                break
            fi
        done
        if [ "$is_alloc" -eq 0 ]; then
            unallocated+=("$i")
        fi
    done

    if [ "${#unallocated[@]}" -ge 2 ]; then
        EMULATOR_PINS+=("${unallocated[0]}")
        IOTHREAD_PINS+=("${unallocated[1]}")
    elif [ "${#unallocated[@]}" -eq 1 ]; then
        EMULATOR_PINS+=("${unallocated[0]}")
        IOTHREAD_PINS+=("${unallocated[0]}")
    else
        # Fallback to core 0 if no cores left
        EMULATOR_PINS+=(0)
        IOTHREAD_PINS+=(0)
    fi
}
