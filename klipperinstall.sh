#!/bin/bash

# Stop script on critical error
set -e

export DEBIAN_FRONTEND=noninteractive

echo "======================================================"
echo "🚀 Starting Kickstart Server - OctoPrint + Klipper v6 Module"
echo "======================================================"

# 1. Cleaning up old host Systemd services (if any)
echo "[1/5] Cleaning up old Systemd services on the host..."
SERVICE_DIR="/etc/systemd/system"
SERVICE_PREFIX="webcam"

for service_file in "$SERVICE_DIR"/${SERVICE_PREFIX}*.service; do
    [ -e "$service_file" ] || continue
    filename=$(basename "$service_file")
    systemctl stop "$filename" 2>/dev/null || true
    systemctl disable "$filename" 2>/dev/null || true
    rm -f "$service_file"
done
systemctl daemon-reload

# 2. Creating directory structure and Docker scripts
echo "[2/5] Creating directory structure and Docker scripts..."
mkdir -p /DATA/stacks/octoprint/webcam-manager
mkdir -p /DATA/AppData/octoprint
# --- KLIPPER DIRECTORIES ---
mkdir -p /DATA/AppData/klipper_config
mkdir -p /DATA/AppData/klipper_run
mkdir -p /DATA/AppData/klipper_logs
touch /DATA/AppData/klipper_config/printer.cfg

# FIX PERMISSIONS: Allow write access for non-root users inside containers
chmod -R 777 /DATA/AppData/octoprint
chmod -R 777 /DATA/AppData/klipper_config
chmod -R 777 /DATA/AppData/klipper_run
chmod -R 777 /DATA/AppData/klipper_logs

# Creating the Entrypoint script to be executed INSIDE the webcam container
cat << 'EOF' > /DATA/stacks/octoprint/webcam-manager/entrypoint.sh
#!/bin/bash

BASE_PORT=10001
SUMMARY_FILE="/tmp/webcams_summary.txt"
rm -f "$SUMMARY_FILE"

echo "====================================================="
echo "🔍 AUTOMATIC WEBCAM ANALYSIS IN PROGRESS..."
echo "====================================================="

raw_list=()

for dev in $(v4l2-ctl --list-devices 2>/dev/null | awk 'NF && /^[^ \t]/ { getline; print $1 }'); do
    [ -e "$dev" ] || continue
    cam_id=$(echo "$dev" | grep -o -E '[0-9]+$')
    cam_name=$(cat "/sys/class/video4linux/video${cam_id}/name" 2>/dev/null || echo "Unknown_Camera")
    phys_path=$(readlink -f "/sys/class/video4linux/video${cam_id}/device" 2>/dev/null || echo "")
    raw_list+=("${cam_name}|${phys_path}|${cam_id}")
done

IFS=$'\n' sorted_list=($(sort <<<"${raw_list[*]}")); unset IFS

echo "====================================================="
echo "📋 DETECTED AND ACTIVATED WEBCAM LIST:"
echo "====================================================="
if [ ${#sorted_list[@]} -eq 0 ]; then
    echo "⚠️ No webcam found."
    exec tail -f /dev/null
else
    for line in "${sorted_list[@]}"; do
        [ -z "$line" ] && continue
        cam_name=$(echo "$line" | cut -d'|' -f1)
        cam_id=$(echo "$line" | cut -d'|' -f3)
        echo " 📷 ${cam_name} (Validated on /dev/video${cam_id})"
    done
fi
echo "====================================================="
echo ""

current_index=0
for line in "${sorted_list[@]}"; do
    [ -z "$line" ] && continue
    cam_name=$(echo "$line" | cut -d'|' -f1)
    cam_id=$(echo "$line" | cut -d'|' -f3)
    port=$((BASE_PORT + current_index))
    
    echo "▶️ Starting stream for [${cam_name}] on port ${port}..."
    mjpg_streamer -i "input_uvc.so -d /dev/video${cam_id} -r 1280x720 -f 10" -o "output_http.so -p ${port} -w /usr/share/mjpg-streamer/www" &
    
    echo " 📷 Camera: ${cam_name}" >> "$SUMMARY_FILE"
    echo "    -> Stream URL   : http://<HOST_IP>:${port}/?action=stream" >> "$SUMMARY_FILE"
    echo "    -> Snapshot URL : http://<HOST_IP>:${port}/?action=snapshot" >> "$SUMMARY_FILE"
    echo "-----------------------------------------------------" >> "$SUMMARY_FILE"
    ((current_index++))
done

echo ""
echo "⏳ The webcam-manager container is ready and active."
wait
EOF

chmod +x /DATA/stacks/octoprint/webcam-manager/entrypoint.sh

# Creating the Dockerfile for the webcam manager
cat << 'EOF' > /DATA/stacks/octoprint/webcam-manager/Dockerfile
FROM alpine:latest
RUN apk add --no-cache bash v4l-utils mjpg-streamer --repository=http://dl-cdn.alpinelinux.org/alpine/edge/testing
COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
EOF

# 3. Preparing the Centralized Docker Compose file
echo "[3/5] Generating centralized Docker Compose file..."
cat << 'EOF' > /DATA/stacks/octoprint/compose.yaml
services:
  octoprint:
    image: octoprint/octoprint:latest
    container_name: octoprint
    restart: unless-stopped
    network_mode: bridge
    privileged: true
    volumes:
      - /DATA/AppData/octoprint:/octoprint
      - /DATA/AppData/klipper_run:/klipper_run
      - /DATA/AppData/klipper_logs:/klipper_logs
      - /DATA/AppData/klipper_config:/klipper_config
      - /dev:/dev
      - /sys:/sys:ro
    ports:
      - "80:80"
    environment:
      - TZ=Europe/Paris
      - ENABLE_MJPG_STREAMER=false

  webcam-manager:
    build: ./webcam-manager
    container_name: octoprint_webcam_manager
    restart: unless-stopped
    privileged: true
    volumes:
      - /dev:/dev
      - /sys:/sys:ro
    ports:
      - "10001-10005:10001-10005"

  klipper:
    image: mkuf/klipper:latest
    container_name: klipper
    restart: unless-stopped
    privileged: true
    network_mode: host
    volumes:
      - /DATA/AppData/klipper_config:/opt/printer_data/config
      - /DATA/AppData/klipper_run:/opt/printer_data/run
      - /DATA/AppData/klipper_logs:/opt/printer_data/logs
      - /dev:/dev
networks: {}
EOF

# 4. Launching, rebuilding, and showing MultiCam setups
echo "[4/5] Aligning and starting containers..."
cd /DATA/stacks/octoprint
docker compose up -d --build

# 5. Automatic Klipper firmware compilation
echo "[5/5] Automatically generating Klipper firmware for Alfawise U20 / Longer LK1..."
echo "Waiting for Klipper container initialization..."

KLIPPER_READY=0
for i in {1..30}; do
    if docker exec klipper [ -d /opt/klipper ] 2>/dev/null; then
        KLIPPER_READY=1
        break
    fi
    sleep 2
done

if [ $KLIPPER_READY -ne 1 ]; then
    echo "❌ Error: The Klipper container did not start in time."
    exit 1
fi

echo ">> Installing build tools in the container (This may take a minute)..."
# Installing dependencies
docker exec -u root klipper bash -c "(apt-get update && apt-get install -y make build-essential gcc-arm-none-eabi binutils-arm-none-eabi libnewlib-arm-none-eabi) || (apk add --no-cache make gcc gcc-arm-none-eabi binutils-arm-none-eabi newlib-arm-none-eabi libc-dev)" >/dev/null 2>&1

echo "========================================================="
echo "🔨 COMPILING BOTH FIRMWARE VERSIONS"
echo "========================================================="
echo "Please wait during compilation (approx. 1 to 2 minutes)..."

# --- 64K VERSION (Recommended) ---
echo ">> 1/2 Compiling 64k version (Recommended)..."
cat << 'CONF_EOF' > /DATA/AppData/kconfig_alfawise_64k
CONFIG_LOW_LEVEL_OPTIONS=y
CONFIG_MACH_STM32=y
CONFIG_BOARD_DIRECTORY="stm32"
CONFIG_MACH_STM32F103=y
CONFIG_STM32_FLASH_START_10000=y
CONFIG_STM32_CLOCK_REF_8M=y
CONFIG_CLOCK_REF_FREQ=8000000
CONFIG_STM32_SERIAL_USART1=y
CONFIG_INITIAL_PINS="!PC4,!PD12"
CONF_EOF

docker cp /DATA/AppData/kconfig_alfawise_64k klipper:/opt/klipper/.config
docker exec -u root klipper bash -c "cd /opt/klipper && make olddefconfig && make clean && make"
mkdir -p /scripts/3d
docker cp klipper:/opt/klipper/out/klipper.bin /scripts/3d/project.bin.64k
rm -f /DATA/AppData/kconfig_alfawise_64k

# --- 32K VERSION (Legacy version) ---
echo ">> 2/2 Compiling 32k version (Legacy)..."
cat << 'CONF_EOF' > /DATA/AppData/kconfig_alfawise_32k
CONFIG_LOW_LEVEL_OPTIONS=y
CONFIG_MACH_STM32=y
CONFIG_BOARD_DIRECTORY="stm32"
CONFIG_MACH_STM32F103=y
CONFIG_STM32_FLASH_START_8000=y
CONFIG_STM32_CLOCK_REF_8M=y
CONFIG_CLOCK_REF_FREQ=8000000
CONFIG_STM32_SERIAL_USART1=y
CONFIG_INITIAL_PINS="!PC4,!PD12"
CONF_EOF

docker cp /DATA/AppData/kconfig_alfawise_32k klipper:/opt/klipper/.config
docker exec -u root klipper bash -c "cd /opt/klipper && make olddefconfig && make clean && make"
docker cp klipper:/opt/klipper/out/klipper.bin /scripts/3d/project.bin.32k
rm -f /DATA/AppData/kconfig_alfawise_32k

LOCAL_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7}' || hostname -I | awk '{print $1}' || echo "YOUR_PC_IP")

echo -e "\n========================================================="
echo "✅ EVERYTHING IS SET UP AND FULLY FUNCTIONAL!"
echo "========================================================="
echo "💡 Your physical cameras have been automatically detected and configured."
echo ""
echo "📋 CONFIGURATION TO ENTER IN YOUR MULTICAM PLUGIN:"
echo "---------------------------------------------------------"

if docker exec octoprint_webcam_manager [ -f /tmp/webcams_summary.txt ] 2>/dev/null; then
    docker exec octoprint_webcam_manager cat /tmp/webcams_summary.txt | sed "s/<HOST_IP>/$LOCAL_IP/g"
else
    echo "⚠️ No webcam was detected when launching the container."
fi

echo "👉 The OctoPrint Web Interface is accessible at: http://${LOCAL_IP}"
echo "========================================================="
echo "📁 WHERE TO FIND YOUR KLIPPER FIRMWARE FILES?"
echo "   Both versions have been generated here on your host machine:"
echo "   -> /scripts/3d/project.bin.64k (Recommended for recent boards)"
echo "   -> /scripts/3d/project.bin.32k (For legacy boards)"
echo ""
echo "⚙️  PRINTER FLASHING PROCEDURE:"
echo "   1. Take a clean micro-SD card (formatted in FAT32)."
echo "   2. Copy the 'project.bin.64k' file onto it."
echo "   3. ⚠️ IMPORTANT: Rename this file exactly to 'project.bin' on the SD card."
echo "   4. Turn off the printer, insert the SD card, then turn it on."
echo "   5. The screen will freeze or stay black: this is normal, Klipper is taking over!"
echo "      (If it doesn't flash, repeat the process with the .32k file)."
echo ""
echo "🔌 OCTOPRINT INTERFACE SETUP:"
echo "   In OctoPrint (Settings > Serial Connection > Additional serial ports),"
echo "   add the exact following line: /klipper_run/printer"
echo "   Save your settings, then connect to this new virtual port."
echo "   Don't forget to install OctoKlipper !"
echo "========================================================="
