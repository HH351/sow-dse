#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

usage() {
    cat <<'EOF'
Usage: ./build.sh [command] [argument]
  host [jobs]        Build the Studio shared library (default command, 8 jobs)
  firmware [jobs]    Build the default FPGA bitstream (16 jobs)
  all [jobs]         Build both the library and firmware (16 jobs)
  program [file]     Program build/board/noc_emulator.bit via JTAG
  access [user]      Grant XDMA access to the sudo caller or named user (root)
  rescan <PCI_BDF>   Re-enumerate PCIe and load XDMA (root)

Project paths are relative to this script. For FPGA commands, put vivado in
PATH or set VIVADO_SETTINGS to its settings64.sh. Host builds need no Vivado.
EOF
}
load_vivado() {
    if [[ -n "${VIVADO_SETTINGS:-}" ]]; then
        # shellcheck disable=SC1090
        source "$VIVADO_SETTINGS"
    fi
    command -v vivado >/dev/null || { echo "Add vivado to PATH or set VIVADO_SETTINGS" >&2; exit 1; }
    mkdir -p build/vivado
}
build_host() {
    cmake -S studio_backend -B build/host -DCMAKE_BUILD_TYPE=Release
    cmake --build build/host --parallel "$1"
}
build_firmware() {
    load_vivado
    vivado -mode batch -log build/vivado/bitstream.log -journal build/vivado/bitstream.jou \
        -source board/ypcb/build_bitstream.tcl -tclargs "$1"
}
need_root() {
    [[ $EUID -eq 0 ]] || { echo "$1 requires root" >&2; exit 1; }
}

case "${1:-host}" in
    host|firmware|all)
        action="${1:-host}"
        jobs="${2:-16}"
        if [[ "$action" == host ]]; then jobs="${2:-8}"; fi
        [[ "$jobs" =~ ^[1-9][0-9]*$ ]] || { echo "jobs must be positive" >&2; exit 2; }
        if [[ "$action" != firmware ]]; then build_host "$jobs"; fi
        if [[ "$action" != host ]]; then build_firmware "$jobs"; fi
        ;;
    program)
        bitstream="${2:-build/board/noc_emulator.bit}"
        [[ -f "$bitstream" ]] || { echo "Bitstream not found: $bitstream" >&2; exit 1; }
        load_vivado
        exec vivado -mode batch -log build/vivado/program.log -journal build/vivado/program.jou \
            -source board/ypcb/program.tcl -tclargs "$bitstream"
        ;;
    access)
        need_root access
        access_user="${2:-${SUDO_USER:-}}"
        [[ -n "$access_user" && "$access_user" != root ]] || { echo "Specify the Studio user" >&2; exit 2; }
        id "$access_user" >/dev/null
        setfacl -m "u:$access_user:rw" /dev/xdma0_h2c_0
        setfacl -m "u:$access_user:r" /dev/xdma0_c2h_0
        ;;
    rescan)
        need_root rescan
        bdf="${2:?Specify PCI_BDF in dddd:bb:ss.f format}"
        [[ "$bdf" =~ ^[[:xdigit:]]{4}:[[:xdigit:]]{2}:[[:xdigit:]]{2}\.[0-7]$ ]] || { echo "Invalid PCI_BDF" >&2; exit 2; }
        if [[ -e "/sys/bus/pci/devices/$bdf/remove" ]]; then
            printf '1\n' > "/sys/bus/pci/devices/$bdf/remove"
        fi
        sleep 1
        printf '1\n' > /sys/bus/pci/rescan
        modprobe xdma
        lspci -s "$bdf" -nnk
        ls -l /dev/xdma0_*
        ;;
    -h|--help|help) usage ;;
    *) usage >&2; exit 2 ;;
esac
