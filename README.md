# Alfawise U20 / Longer LK1 - Klipper & OctoPrint Docker Setup
A complete, automated deployment script to bring the power of Klipper and OctoPrint to your Alfawise U20 or Longer LK1 3D printer using Docker.

This repository provides a seamless, one-click installation that sets up OctoPrint, Klipper, and a robust Webcam Manager in isolated containers. It also automatically compiles the correct Klipper firmware for your specific motherboard!

## ✨ Features
🐳 Fully Dockerized Environment: Runs OctoPrint, Klipper, and a custom Webcam Manager in lightweight, isolated containers via Docker Compose.

⚙️ Automated Firmware Compilation: The script automatically generates the correct Klipper firmware (.bin files) for both 64k (recommended) and 32k bootloaders specifically tuned for the STM32F103 chip.

📷 Plug & Play Multi-Cam Support: Automatically detects physical webcams connected to your host and exposes them as MJPEG streams.

🖨️ Ready-to-use printer.cfg: Includes a pre-configured, safe, and optimized Klipper configuration for a stock Alfawise U20 / Longer LK1 (no BLTouch).

📂 Automated Volume Mapping: Properly handles Linux permissions and volume mapping so OctoPrint's OctoKlipper plugin can read/write Klipper configs seamlessly.

## 🛠️ Prerequisites
A host machine running Linux (Raspberry Pi OS, Ubuntu, Debian, etc.).

Docker and Docker Compose installed.

An Alfawise U20 or Longer LK1 connected via USB to your host.

## 🚀 Installation & Usage

### 1. Run the Deployment Script
Clone this repository or download the installoctoprint.sh script, make it executable, and run it with sudo:

chmod +x klipperinstall.sh

sudo ./klipperinstall.sh

The script will:
- Clean up any old webcam systemd services.
- Build the Docker environment.
- Automatically compile the Klipper firmware for your printer.

### 2. Flash the Printer
Once the script finishes, it will generate two firmware files on your host machine (usually in /scripts/3d/):

- project.bin.64k (Recommended for newer boards)
- project.bin.32k (For older legacy boards)

Take a clean micro-SD card formatted in FAT32.

Copy project.bin.64k to the SD card.

⚠️ IMPORTANT: Rename the file exactly to *project.bin*

Insert the SD card into your powered-off printer, then turn it on.

The screen will remain blank/frozen. This is normal—Klipper has taken over !

⚠️ IMPORTANT: if the progressbar is stuck, it likely didn't work ! 

### 3. Configure OctoPrint
Access the OctoPrint Web Interface at http://<YOUR_HOST_IP>.

Go to Settings > Serial Connection > General.

Under Additional serial ports, add exactly: /klipper_run/printer

Save, and connect OctoPrint using this new virtual port.

⚙️ Klipper Configuration (printer.cfg)
The provided printer.cfg is tailored for a stock Alfawise U20 / Longer LK1.

Key Configuration Details:

- Build Volume: 300x300x400 mm
- Microcontroller: STM32F103 (USART1 PB10/PB9)
- Bootloader: 64k offset
- Kinematics: Cartesian (Max Velocity: 300mm/s, Max Accel: 3000mm/s²)
- Safety Limits: Minimum extrusion temperature is set to 170°C.

### 📝 Post-Installation Steps
PID Tuning: The config includes default PID values, but you should run a PID tune for your specific environment. In the OctoPrint terminal, run:

- Hotend: PID_CALIBRATE HEATER=extruder TARGET=200
- Bed: PID_CALIBRATE HEATER=heater_bed TARGET=60

Save the settings with SAVE_CONFIG.

Extrusion Distance: By default, Klipper limits single extrusions to 50mm. If you need to extrude more (e.g., for E-step calibration), uncomment the #max_extrude_only_distance: 150.0 line in the [extruder] section of your printer.cfg.

Pressure Advance: Set to 0.4392 as a baseline. Adjust this value based on your filament type (PLA, PETG, etc.).

### 🐛 Troubleshooting
#### Permission Denied when editing printer.cfg in OctoPrint:
If OctoKlipper refuses to save changes to your config file, fix the permissions on your host by running:
sudo chmod -R 777 /DATA/AppData/klipper_config/

#### Cannot extrude manually:
Ensure your hotend is heated above 170°C. Klipper's cold-extrusion prevention will block the extruder motor otherwise. Also, ensure your interface is sending relative extrusion commands (M83).
