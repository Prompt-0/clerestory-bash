#!/usr/bin/env bash
# Libvirt Domain XML Synthesis Module for Clerestory (Bash)
set -euo pipefail

synthesize_libvirt_xml() {
    local vm_name="$1"
    local ram_mb="$2"
    local vcpus="$3"
    local disk_path="$4"
    local oem_path="$5"
    local iso_path="$6"
    local gpu_mode="$7"
    local vfio_pci="${8:-}"
    local gvt_uuid="${9:-}"
    local lg_shm="${10:-64}"
    local share_dir="${11:-}"
    local ovmf_code="${12:-/usr/share/edk2/ovmf/OVMF_CODE.secboot.fd}"
    local ovmf_vars="${13:-/usr/share/edk2/ovmf/OVMF_VARS.secboot.fd}"
    local is_amd="${14:-0}"
    local queues="${15:-8}"

    local total_cores=$((vcpus / 2))
    [ "$total_cores" -eq 0 ] && total_cores=1

    cat << XML
<domain type='kvm'>
  <name>${vm_name}</name>
  <memory unit='MiB'>${ram_mb}</memory>
  <currentMemory unit='MiB'>${ram_mb}</currentMemory>
  <vcpu placement='static'>${vcpus}</vcpu>
  <iothreads>1</iothreads>
  <cputune>
XML

    for pin in "${VCPU_PINS[@]}"; do
        local v_id="${pin%%:*}"
        local h_id="${pin##*:}"
        echo "    <vcpupin vcpu='${v_id}' cpuset='${h_id}'/>"
    done

    if [ "${#EMULATOR_PINS[@]}" -gt 0 ]; then
        local emu_str=$(IFS=,; echo "${EMULATOR_PINS[*]}")
        echo "    <emulatorpin cpuset='${emu_str}'/>"
    fi

    if [ "${#IOTHREAD_PINS[@]}" -gt 0 ]; then
        local io_str=$(IFS=,; echo "${IOTHREAD_PINS[*]}")
        echo "    <iothreadpin iothread='1' cpuset='${io_str}'/>"
    fi

    cat << XML
  </cputune>
  <memoryBacking>
    <source type='memfd'/>
    <access mode='shared'/>
  </memoryBacking>
  <os firmware='efi'>
    <type arch='x86_64' machine='q35'>hvm</type>
    <firmware>
      <feature enabled='yes' name='secure-boot'/>
      <feature enabled='yes' name='enrolled-keys'/>
    </firmware>
    <loader readonly='yes' type='pflash'>${ovmf_code}</loader>
    <nvram template='${ovmf_vars}'>/var/lib/libvirt/qemu/nvram/${vm_name}_VARS.fd</nvram>
    <boot dev='hd'/>
    <boot dev='cdrom'/>
  </os>
  <features>
    <acpi/>
    <apic/>
    <hyperv mode='custom'>
      <relaxed state='on'/>
      <vapic state='on'/>
      <spinlocks state='on' retries='8191'/>
      <vpindex state='on'/>
      <runtime state='on'/>
      <synic state='on'/>
      <stimer state='on'>
        <direct state='on'/>
      </stimer>
      <reset state='on'/>
      <frequencies state='on'/>
      <reenlightenment state='on'/>
      <tlbflush state='on'/>
      <ipi state='on'/>
    </hyperv>
    <kvm>
      <hidden state='on'/>
    </kvm>
    <ioapic driver='kvm'/>
  </features>
  <cpu mode='host-passthrough' check='none' migratable='off'>
    <topology sockets='1' dies='1' cores='${total_cores}' threads='2'/>
    <feature policy='require' name='invtsc'/>
    <feature policy='require' name='tsc-deadline'/>
XML

    if [ "$is_amd" -eq 1 ]; then
        echo "    <feature policy='require' name='topoext'/>"
    fi

    cat << XML
  </cpu>
  <clock offset='localtime'>
    <timer name='rtc' tickpolicy='catchup'/>
    <timer name='pit' tickpolicy='discard'/>
    <timer name='hpet' present='no'/>
    <timer name='kvmclock' present='no'/>
    <timer name='hypervclock' present='yes'/>
    <timer name='tsc' present='yes' mode='native'/>
  </clock>
  <devices>
    <emulator>/usr/bin/qemu-system-x86_64</emulator>
    <controller type='scsi' model='virtio-scsi' index='0'>
      <driver iothread='1' queues='${queues}'/>
    </controller>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2' cache='none' io='io_uring' discard='unmap' detect_zeroes='unmap'/>
      <source file='${disk_path}'/>
      <target dev='sda' bus='scsi'/>
      <address type='drive' controller='0' bus='0' target='0' unit='0'/>
    </disk>
XML

    if [ -n "$oem_path" ] && [ -f "$oem_path" ]; then
        cat << XML
    <disk type='file' device='cdrom'>
      <driver name='qemu' type='raw'/>
      <source file='${oem_path}'/>
      <target dev='sdb' bus='scsi'/>
      <readonly/>
      <address type='drive' controller='0' bus='0' target='0' unit='1'/>
    </disk>
XML
    fi

    if [ -n "$iso_path" ]; then
        cat << XML
    <disk type='file' device='cdrom'>
      <driver name='qemu' type='raw'/>
      <source file='${iso_path}'/>
      <target dev='sdc' bus='scsi'/>
      <readonly/>
      <address type='drive' controller='0' bus='0' target='0' unit='2'/>
    </disk>
XML
    fi

    cat << XML
    <tpm model='tpm-crb'>
      <backend type='emulator' version='2.0'/>
    </tpm>
    <interface type='network'>
      <source network='default'/>
      <model type='virtio'/>
    </interface>
    <sound model='ich9'>
      <audio id='1'/>
    </sound>
    <audio id='1' type='pipewire'/>
XML

    if [ -n "$share_dir" ]; then
        cat << XML
    <filesystem type='mount' accessmode='passthrough'>
      <driver type='virtiofs' queue='1024'/>
      <binary path='/usr/libexec/virtiofsd' xattr='on'/>
      <source dir='${share_dir}'/>
      <target dir='clerestory_share'/>
    </filesystem>
XML
    fi

    case "$gpu_mode" in
        "spice")
            cat << XML
    <graphics type='spice' autoport='yes'>
      <listen type='address'/>
      <image compression='off'/>
      <gl enable='no'/>
    </graphics>
    <video>
      <model type='qxl' ram='65536' vram='65536' vgamem='16384' heads='1' primary='yes'/>
    </video>
XML
            ;;
        "looking-glass")
            cat << XML
    <shmem name='looking-glass'>
      <model type='ivshmem-plain'/>
      <size unit='M'>${lg_shm}</size>
    </shmem>
    <graphics type='spice' autoport='yes'>
      <listen type='address'/>
    </graphics>
    <video>
      <model type='qxl' ram='65536' vram='65536' heads='1' primary='yes'/>
    </video>
XML
            ;;
        "gvt-g")
            cat << XML
    <hostdev mode='subsystem' type='mdev' managed='no' model='vfio-pci' display='on'>
      <source>
        <address uuid='${gvt_uuid}'/>
      </source>
    </hostdev>
    <graphics type='spice' autoport='yes'>
      <listen type='address'/>
    </graphics>
XML
            ;;
        "vfio")
            if [ -n "$vfio_pci" ]; then
                IFS=: read -r dom bus rest <<< "$vfio_pci"
                IFS=. read -r slot func <<< "$rest"
                cat << XML
    <hostdev mode='subsystem' type='pci' managed='yes'>
      <source>
        <address domain='0x${dom}' bus='0x${bus}' slot='0x${slot}' function='0x${func}'/>
      </source>
    </hostdev>
XML
            fi
            ;;
    esac

    cat << XML
    <channel type='unix'>
      <target type='virtio' name='org.qemu.guest_agent.0'/>
    </channel>
  </devices>
</domain>
XML
}
