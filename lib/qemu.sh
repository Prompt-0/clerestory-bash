#!/usr/bin/env bash
# Standalone QEMU Runner Script Synthesizer (Bash)
set -euo pipefail

synthesize_qemu_script() {
    local vm_name="$1"
    local ram_mb="$2"
    local vcpus="$3"
    local disk_path="$4"
    local oem_path="$5"
    local iso_path="$6"
    local queues="${7:-8}"

    local total_cores=$((vcpus / 2))
    [ "$total_cores" -eq 0 ] && total_cores=1

    cat << SCRIPT
#!/usr/bin/env bash
# Auto-generated standalone Windows 11 launcher by Clerestory (Bash)
set -euo pipefail

qemu-system-x86_64 \\
  -name '${vm_name}' \\
  -enable-kvm \\
  -machine q35,smm=on,accel=kvm \\
  -m ${ram_mb}M \\
  -smp ${vcpus},sockets=1,cores=${total_cores},threads=2 \\
  -cpu host,migratable=off,+invtsc,+tsc-deadline,hv_relaxed,hv_vapic,hv_spinlocks=0x1fff,hv_vpindex,hv_runtime,hv_synic,hv_stimer,hv_stimer_direct,hv_frequencies,hv_tlbflush,hv_ipi,hv_reenlightenment \\
  -device virtio-scsi-pci,id=scsi0,iothread=iothread0,num_queues=${queues} \\
  -object iothread,id=iothread0 \\
  -drive file='${disk_path}',if=none,id=drive0,format=qcow2,cache=none,aio=io_uring \\
  -device scsi-hd,drive=drive0,bus=scsi0.0,id=hd0,discard_granularity=512 \\
SCRIPT

    if [ -n "$oem_path" ] && [ -f "$oem_path" ]; then
        cat << SCRIPT
  -drive file='${oem_path}',if=none,id=oemdrv,format=raw,media=cdrom,readonly=on \\
  -device scsi-cd,drive=oemdrv,bus=scsi0.0,id=cd0 \\
SCRIPT
    fi

    if [ -n "$iso_path" ]; then
        cat << SCRIPT
  -drive file='${iso_path}',if=none,id=winiso,format=raw,media=cdrom,readonly=on \\
  -device scsi-cd,drive=winiso,bus=scsi0.0,id=cd1 \\
SCRIPT
    fi

    cat << SCRIPT
  -netdev user,id=net0 -device virtio-net-pci,netdev=net0 \\
  -vga qxl -spice port=5900,disable-ticketing=on \\
  -device virtio-serial-pci -device virtserialport,chardev=qga0,name=org.qemu.guest_agent.0 \\
  -chardev socket,path=/tmp/qga.sock,server=on,wait=off,id=qga0
SCRIPT
}
