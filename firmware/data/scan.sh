#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  Nixo Soft PC Checker — Linux/Mac Diagnostic Script
#  Runs on target PC, sends results to ESP32 dongle
# ═══════════════════════════════════════════════════════════════

DONGLE_URL="http://192.168.4.1"
RESULTS="{}"

C='\033[0;36m'; G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'
GOLD='\033[0;33m'; W='\033[1;37m'; D='\033[2m'; NC='\033[0m'

echo ""
echo -e "${GOLD}  ╔═══════════════════════════════════════╗${NC}"
echo -e "${GOLD}  ║   Nixo Soft PC Checker v2.0           ║${NC}"
echo -e "${GOLD}  ║   Hardware Diagnostic Scanner         ║${NC}"
echo -e "${GOLD}  ╚═══════════════════════════════════════╝${NC}"
echo ""
echo -e "${C}  Scanning hardware...${NC}"
echo ""

PLATFORM="linux"
if [[ "$(uname)" == "Darwin" ]]; then
    PLATFORM="mac"
fi

# Temp file for building JSON
TMP="/tmp/nixosoft-scan-$$.json"

# ─── Helper: JSON escape ────────────────────────────────────
json_escape() {
    echo -n "$1" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo "\"$1\""
}

# ─── CPU ─────────────────────────────────────────────────────
echo -e "  ${D}[1/9] CPU...${NC}"
if [[ "$PLATFORM" == "mac" ]]; then
    CPU_NAME=$(sysctl -n machdep.cpu.brand_string 2>/dev/null)
    CPU_CORES=$(sysctl -n hw.physicalcpu 2>/dev/null)
    CPU_THREADS=$(sysctl -n hw.logicalcpu 2>/dev/null)
    CPU_FREQ=$(sysctl -n hw.cpufrequency 2>/dev/null)
    CPU_MHZ=$((CPU_FREQ / 1000000))
else
    CPU_NAME=$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs)
    CPU_CORES=$(grep -c "^processor" /proc/cpuinfo 2>/dev/null)
    CPU_THREADS=$(nproc 2>/dev/null || echo "$CPU_CORES")
    CPU_MHZ=$(grep -m1 "cpu MHz" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs | cut -d. -f1)
    CPU_CACHE=$(grep -m1 "cache size" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs)
fi
echo -e "    ${W}${CPU_NAME}${NC}"

# ─── Memory ──────────────────────────────────────────────────
echo -e "  ${D}[2/9] Memory...${NC}"
if [[ "$PLATFORM" == "mac" ]]; then
    MEM_BYTES=$(sysctl -n hw.memsize 2>/dev/null)
    MEM_GB=$((MEM_BYTES / 1073741824))
    MEM_INFO="[]"
else
    MEM_KB=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}')
    MEM_GB=$((MEM_KB / 1048576))
    # Get DIMM info via dmidecode (needs sudo)
    MEM_INFO="[]"
    if command -v dmidecode &>/dev/null; then
        MEM_INFO=$(sudo dmidecode -t memory 2>/dev/null | grep -E "Size:|Speed:|Type:" | head -20 || echo "[]")
    fi
fi
echo -e "    ${W}${MEM_GB}GB RAM${NC}"

# ─── GPU ─────────────────────────────────────────────────────
echo -e "  ${D}[3/9] GPU...${NC}"
GPU_LIST="[]"
if [[ "$PLATFORM" == "mac" ]]; then
    GPU_NAME=$(system_profiler SPDisplaysDataType 2>/dev/null | grep "Chipset Model" | cut -d: -f2 | xargs)
    GPU_VRAM=$(system_profiler SPDisplaysDataType 2>/dev/null | grep "VRAM" | cut -d: -f2 | xargs)
    echo -e "    ${W}${GPU_NAME} (${GPU_VRAM})${NC}"
else
    if command -v lspci &>/dev/null; then
        GPU_NAME=$(lspci 2>/dev/null | grep -i "vga\|3d\|display" | head -1 | cut -d: -f3 | xargs)
        echo -e "    ${W}${GPU_NAME:-No discrete GPU detected}${NC}"
    fi
fi

# ─── Storage ─────────────────────────────────────────────────
echo -e "  ${D}[4/9] Storage...${NC}"
if [[ "$PLATFORM" == "mac" ]]; then
    DISK_INFO=$(diskutil list 2>/dev/null | head -20)
    DISK_SIZE=$(diskutil info disk0 2>/dev/null | grep "Disk Size" | awk -F'(' '{print $1}' | cut -d: -f2 | xargs)
    echo -e "    ${W}${DISK_SIZE}${NC}"
else
    DISK_INFO=$(lsblk -d -o NAME,SIZE,TYPE,MODEL,ROTA 2>/dev/null | grep disk)
    echo "$DISK_INFO" | while read line; do
        echo -e "    ${W}${line}${NC}"
    done
fi

# SMART data
SMART_DATA=""
if command -v smartctl &>/dev/null; then
    BOOT_DISK=$(mount | grep "on / " | head -1 | awk '{print $1}' | sed 's/[0-9]*$//' | sed 's/p$//')
    SMART_DATA=$(sudo smartctl -a "$BOOT_DISK" 2>/dev/null | head -30)
fi

# ─── Motherboard ─────────────────────────────────────────────
echo -e "  ${D}[5/9] Motherboard...${NC}"
if [[ "$PLATFORM" == "mac" ]]; then
    BOARD_NAME=$(system_profiler SPHardwareDataType 2>/dev/null | grep "Model Name" | cut -d: -f2 | xargs)
    BOARD_SERIAL=$(system_profiler SPHardwareDataType 2>/dev/null | grep "Serial" | cut -d: -f2 | xargs)
    echo -e "    ${W}${BOARD_NAME}${NC}"
else
    BOARD_MFG=$(cat /sys/devices/virtual/dmi/id/board_vendor 2>/dev/null || echo "Unknown")
    BOARD_NAME=$(cat /sys/devices/virtual/dmi/id/board_name 2>/dev/null || echo "Unknown")
    BIOS_VER=$(cat /sys/devices/virtual/dmi/id/bios_version 2>/dev/null || echo "Unknown")
    echo -e "    ${W}${BOARD_MFG} ${BOARD_NAME}${NC}"
fi

# ─── Network ────────────────────────────────────────────────
echo -e "  ${D}[6/9] Network...${NC}"
if [[ "$PLATFORM" == "mac" ]]; then
    NET_INFO=$(networksetup -listallhardwareports 2>/dev/null | head -20)
else
    NET_INFO=$(ip link show 2>/dev/null | grep -E "^[0-9]" | awk '{print $2}' | tr -d ':')
fi

# ─── USB ────────────────────────────────────────────────────
echo -e "  ${D}[7/9] USB & Peripherals...${NC}"
if command -v lsusb &>/dev/null; then
    USB_COUNT=$(lsusb 2>/dev/null | wc -l)
    USB_3=$(lsusb 2>/dev/null | grep -ci "3.0\|3.1\|3.2" || echo 0)
else
    USB_COUNT=0
    USB_3=0
fi

# ─── Thermals ───────────────────────────────────────────────
echo -e "  ${D}[8/9] Thermals...${NC}"
TEMPS=""
if [[ "$PLATFORM" == "mac" ]]; then
    # macOS doesn't expose temps easily without tools
    TEMPS="N/A"
else
    if command -v sensors &>/dev/null; then
        TEMPS=$(sensors 2>/dev/null | grep -E "°C" | head -5)
    elif [ -f /sys/class/thermal/thermal_zone0/temp ]; then
        TEMP_RAW=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
        TEMPS="CPU: $((TEMP_RAW / 1000))°C"
    fi
fi

# ─── Disk Speed Test ────────────────────────────────────────
echo -e "  ${D}[9/9] Disk speed test...${NC}"
TEST_FILE="/tmp/nixosoft_disktest_$$"
TEST_SIZE=100  # MB

# Write test
WRITE_SPEED=$(dd if=/dev/zero of="$TEST_FILE" bs=1M count=$TEST_SIZE conv=fdatasync 2>&1 | grep -oP '[\d.]+ [MG]B/s' || echo "N/A")

# Read test  
echo 3 | sudo tee /proc/sys/vm/drop_caches &>/dev/null  # Clear cache
READ_SPEED=$(dd if="$TEST_FILE" of=/dev/null bs=1M 2>&1 | grep -oP '[\d.]+ [MG]B/s' || echo "N/A")

rm -f "$TEST_FILE"
echo -e "    ${W}Read: ${READ_SPEED}, Write: ${WRITE_SPEED}${NC}"

# ─── Build JSON Results ──────────────────────────────────────
echo ""
echo -e "${C}  Building results...${NC}"

cat > "$TMP" << JSONEOF
{
  "platform": "${PLATFORM}",
  "hostname": "$(hostname)",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%S)",
  "cpu": {
    "name": "${CPU_NAME}",
    "cores": ${CPU_CORES:-0},
    "threads": ${CPU_THREADS:-0},
    "maxClockMHz": ${CPU_MHZ:-0}
  },
  "memory": {
    "totalGB": ${MEM_GB:-0}
  },
  "gpu": [{
    "name": "${GPU_NAME:-Unknown}"
  }],
  "storage": [{
    "model": "$(lsblk -d -o MODEL 2>/dev/null | tail -1 | xargs || echo 'Unknown')",
    "sizeGB": $(lsblk -d -b -o SIZE 2>/dev/null | tail -1 | awk '{printf "%.0f", $1/1073741824}' || echo 0),
    "type": "$([ "$(cat /sys/block/$(mount | grep 'on / ' | awk '{print $1}' | sed 's|/dev/||' | sed 's/[0-9]*$//')/queue/rotational 2>/dev/null)" = "0" ] && echo "SSD" || echo "HDD")"
  }],
  "motherboard": {
    "manufacturer": "${BOARD_MFG:-Unknown}",
    "product": "${BOARD_NAME:-Unknown}"
  },
  "diskSpeed": {
    "readSpeed": "${READ_SPEED}",
    "writeSpeed": "${WRITE_SPEED}"
  },
  "usb": {
    "devices": ${USB_COUNT:-0}
  },
  "os": {
    "name": "$(uname -s) $(uname -r)",
    "arch": "$(uname -m)"
  }
}
JSONEOF

# ─── Send Results ────────────────────────────────────────────
echo -e "${C}  Sending results to dongle...${NC}"

RESPONSE=$(curl -s -X POST "$DONGLE_URL/api/results" \
  -H "Content-Type: application/json" \
  -d @"$TMP" \
  --connect-timeout 5 \
  --max-time 10 2>/dev/null)

if echo "$RESPONSE" | grep -q "ok"; then
    echo ""
    echo -e "  ${G}✓ Results sent successfully!${NC}"
    echo -e "  ${D}Open the dashboard on your phone to view scores.${NC}"
else
    echo ""
    echo -e "  ${R}✗ Failed to send results${NC}"
    echo -e "  ${Y}Make sure PC is connected to NixoSoft-Check WiFi${NC}"
    echo -e "  ${D}Results saved to: ${TMP}${NC}"
fi

rm -f "$TMP"

echo ""
echo -e "${GOLD}  ╔═══════════════════════════════════════╗${NC}"
echo -e "${GOLD}  ║   Scan complete! Check your phone.    ║${NC}"
echo -e "${GOLD}  ╚═══════════════════════════════════════╝${NC}"
echo ""
