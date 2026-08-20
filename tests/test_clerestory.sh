#!/usr/bin/env bash
# Automated Test Suite for Clerestory (Bash)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${SCRIPT_DIR}/clerestory.sh"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

echo "=== Running Clerestory (Bash) Test Suite ==="

# Test 1: Doctor execution
echo -n "[Test 1/5] Testing 'doctor' output... "
"$BIN" doctor > /dev/null
echo "PASSED"

# Test 2: XML Synthesis & Schema Validation for Spice Mode
echo -n "[Test 2/5] Testing 'create --dry-run' XML with virt-xml-validate (Spice)... "
"$BIN" create --name test-spice --iso /dev/null --gpu-mode spice --dry-run > "${TEMP_DIR}/spice.txt"
sed -n '/<domain/,/<\/domain>/p' "${TEMP_DIR}/spice.txt" > "${TEMP_DIR}/spice.xml"
virt-xml-validate "${TEMP_DIR}/spice.xml" > /dev/null 2>&1
echo "PASSED"

# Test 3: XML Synthesis & Schema Validation for Looking Glass & GVT-g Modes
echo -n "[Test 3/5] Testing 'create --dry-run' XML with virt-xml-validate (Looking Glass & GVT-g)... "
"$BIN" create --name test-lg --iso /dev/null --gpu-mode looking-glass --looking-glass-shm 128 --dry-run > "${TEMP_DIR}/lg.txt"
sed -n '/<domain/,/<\/domain>/p' "${TEMP_DIR}/lg.txt" > "${TEMP_DIR}/lg.xml"
virt-xml-validate "${TEMP_DIR}/lg.xml" > /dev/null 2>&1

"$BIN" create --name test-gvt --iso /dev/null --gpu-mode gvt-g --gvt-uuid "00000000-0000-0000-0000-000000000001" --dry-run > "${TEMP_DIR}/gvt.txt"
sed -n '/<domain/,/<\/domain>/p' "${TEMP_DIR}/gvt.txt" > "${TEMP_DIR}/gvt.xml"
virt-xml-validate "${TEMP_DIR}/gvt.xml" > /dev/null 2>&1
echo "PASSED"

# Test 4: Virtual FAT32 OEMDRV & autounattend.xml generation
echo -n "[Test 4/5] Testing virtual FAT32 OEMDRV volume & answer file... "
source "${SCRIPT_DIR}/lib/slipstream.sh"
build_oemdrv_fat_disk "${TEMP_DIR}/oemdrv.img" "TestAdmin" "Pass123!"
[ -f "${TEMP_DIR}/oemdrv.img" ]
# Verify autounattend.xml exists inside the FAT32 image using mdir
mdir -i "${TEMP_DIR}/oemdrv.img" "::autounattend.xml" > /dev/null 2>&1
# Extract and verify content
mcopy -i "${TEMP_DIR}/oemdrv.img" "::autounattend.xml" "${TEMP_DIR}/extracted.xml"
grep -q "<Name>TestAdmin</Name>" "${TEMP_DIR}/extracted.xml"
grep -q "BypassTPMCheck" "${TEMP_DIR}/extracted.xml"
grep -q "qemu-ga-x86_64.msi" "${TEMP_DIR}/extracted.xml"
echo "PASSED"

# Test 5: Subcommand completions and JSON output
echo -n "[Test 5/5] Testing CLI subcommands and JSON serialization... "
"$BIN" completions > /dev/null
"$BIN" inspect "test-vm" > /dev/null
"$BIN" list > /dev/null
"$BIN" create --name test-json --iso /dev/null --json | grep -q '"name": "test-json"'
echo "PASSED"

echo ""
echo "🎉 ALL 5 TEST SUITES PASSED CLEANLY!"
