# Nixo Soft PC Checker Dongle

**Instant hardware diagnostics from a USB dongle. No reboot. No installation. Just plug and scan.**

The PC Checker Dongle is an ESP32-S3 USB device that diagnoses any PC's hardware and shows results on your phone — all without touching the target machine's OS.

🌐 **Product page:** [nixosoft.com/dongle](https://nixosoft.com/dongle)

---

## How It Works

1. **Plug** the dongle into any PC's USB-A port
2. **Connect** your phone to the `NixoSoft-Check` WiFi network (open, no password)
3. **Scan** the QR code on the dongle's built-in LCD screen
4. **Select** your target OS (Windows / Linux / Mac) and a test profile
5. **Tap "Run Scan"** — the dongle types diagnostic commands on the PC via USB HID keyboard emulation
6. **View results** on your phone dashboard with scores, grades, and full hardware breakdown
7. **Export** a professional PDF report

---

## Compatible Hardware

| Spec | Details |
|------|---------|
| **Board** | [LILYGO T-Dongle-S3](https://www.lilygo.cc/products/t-dongle-s3) |
| **Chip** | ESP32-S3 (dual-core Xtensa LX7, 240 MHz) |
| **Display** | 0.96" ST7735 TFT LCD (80×160 pixels) |
| **Flash** | 16 MB |
| **USB** | Native USB OTG — HID keyboard + CDC serial |
| **WiFi** | 802.11 b/g/n (creates its own access point) |
| **Form Factor** | USB-A dongle |

### Where to Buy

- **AliExpress** — Search "LILYGO T-Dongle S3" (~$8–15 USD)
- **Amazon** — Search "LILYGO T-Dongle S3" (~$15–20 USD)
- **LILYGO Official Store** — [lilygo.cc](https://www.lilygo.cc/products/t-dongle-s3)

---

## Firmware Installation

### Prerequisites

- [Visual Studio Code](https://code.visualstudio.com/) with the [PlatformIO extension](https://platformio.org/install/ide?install=vscode)
  - Or: [PlatformIO CLI](https://docs.platformio.org/en/latest/core/installation/index.html) standalone
- A USB-C cable (for initial flashing only — the dongle's USB-C port)
- The LILYGO T-Dongle-S3 hardware

### Step 1: Clone This Repository

```bash
git clone https://github.com/Nixosoft/pc-checker-dongle.git
cd pc-checker-dongle
```

### Step 2: Open in VS Code

Open the `firmware/` folder in VS Code. PlatformIO should auto-detect the project from `platformio.ini`.

If using PlatformIO CLI instead:
```bash
cd firmware
```

### Step 3: Connect the Dongle

Plug the dongle into your computer using a **USB-C cable** (not via the USB-A plug — that's for target PCs).

> **First-time flash?** You may need to put the board into download mode:
> 1. Hold the **BOOT** button on the dongle
> 2. While holding, briefly press the **RESET** button
> 3. Release both — the dongle is now in flash mode

### Step 4: Flash the Firmware

**VS Code:** Click the PlatformIO "Upload" button (→ arrow icon) in the bottom toolbar.

**CLI:**
```bash
pio run --target upload
```

Wait for the upload to complete. You should see `SUCCESS` in the output.

### Step 5: Upload the Dashboard & Scripts to SPIFFS

The dongle serves a web dashboard and diagnostic scripts from its internal flash storage (SPIFFS). You need to upload these separately.

**VS Code:** Open the PlatformIO sidebar → Project Tasks → `t-dongle-s3` → `Upload Filesystem Image`

**CLI:**
```bash
pio run --target uploadfs
```

### Step 6: Verify

Unplug the USB-C cable and plug the dongle into any PC via its **USB-A** connector.

You should see:
- The Nixo Soft splash screen on the LCD
- A QR code pointing to `http://192.168.4.1`
- The `NixoSoft-Check` WiFi network appearing on your phone

If all three work — you're done! 🎉

---

## Troubleshooting

### Dongle not detected when flashing
- Try a different USB-C cable (some are charge-only, no data)
- Use the BOOT + RESET button sequence described in Step 3
- On Windows: install [CP210x drivers](https://www.silabs.com/developers/usb-to-uart-bridge-vcp-drivers) if the port doesn't appear
- On Linux: make sure your user is in the `dialout` group: `sudo usermod -aG dialout $USER`

### Upload fails with timeout
- Reduce upload speed: edit `platformio.ini`, change `upload_speed` to `460800` or `115200`
- Try a different USB port (avoid USB hubs)

### QR code shows but WiFi doesn't appear
- The ESP32-S3's WiFi AP takes 2–3 seconds to start after boot
- If it still doesn't appear, reflash the firmware — SPIFFS may be corrupted

### Dashboard loads but scan doesn't work
- Make sure the dongle's USB-A end is firmly plugged into the target PC
- Some BIOS/OS security settings block HID devices — try a different USB port
- On Mac: grant "Input Monitoring" permission when prompted

### "No script for this OS" error
- Make sure you completed Step 5 (SPIFFS upload) — the scripts live in flash storage

---

## Test Profiles

Each profile weights hardware components differently:

| Profile | CPU | GPU | RAM | Storage | Thermal |
|---------|-----|-----|-----|---------|---------|
| 🤖 AI / ML | 20% | 40% | 25% | 10% | 5% |
| 🎮 Gaming | 25% | 35% | 15% | 15% | 10% |
| 🎬 Video / 3D | 30% | 30% | 15% | 20% | 5% |
| 💻 Developer | 30% | 10% | 25% | 25% | 10% |
| 🎵 Music Production | 35% | 5% | 25% | 25% | 10% |
| 🖥️ Server | 25% | 5% | 25% | 20% | 25% |
| 📊 Office | 25% | 15% | 25% | 25% | 10% |
| ⛏️ Mining | 10% | 45% | 10% | 5% | 30% |

---

## API Endpoints

The dongle runs a web server at `http://192.168.4.1` with these endpoints:

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Mobile dashboard (single-page app) |
| `/scan.ps1` | GET | Windows diagnostic script (PowerShell) |
| `/scan.sh` | GET | Linux/Mac diagnostic script (Bash) |
| `/api/status` | GET | Dongle state, firmware version, connection info |
| `/api/scan` | POST | Trigger USB HID keyboard — types diagnostic commands on target PC |
| `/api/results` | POST | Receive diagnostic results from the running script |
| `/api/results` | GET | Fetch results (phone polls this while scan is running) |
| `/api/reset` | POST | Reset state for a new scan |
| `/api/info` | GET | Firmware version, chip info, uptime, free memory |

---

## Project Structure

```
pc-checker-dongle/
├── firmware/
│   ├── platformio.ini          # PlatformIO build configuration
│   ├── src/
│   │   └── main.cpp            # ESP32-S3 firmware (WiFi AP, HID, LCD, web server)
│   ├── data/                   # SPIFFS — uploaded to dongle's flash storage
│   │   ├── index.html          # Mobile dashboard (self-contained, ~16 KB)
│   │   ├── scan.ps1            # Windows diagnostic script (PowerShell)
│   │   └── scan.sh             # Linux/Mac diagnostic script (Bash)
│   └── lib/                    # Local libraries (if any)
├── LICENSE                     # Personal Use License
└── README.md
```

---

## ISO vs Dongle

Already have the [PC Checker ISO](https://nixosoft.com)? Here's how they compare:

| Feature | Bootable ISO | USB Dongle |
|---------|-------------|------------|
| **Cost** | Free download | ~$15–20 hardware |
| **Requires reboot** | Yes | No |
| **Works with running OS** | No | Yes |
| **Hardware access depth** | Full (bare metal) | Via OS commands |
| **Setup time** | Flash USB + reboot | Plug in |
| **Target PC storage** | Zero footprint | Zero footprint |
| **Phone dashboard** | ✓ | ✓ |
| **PDF report** | ✓ | ✓ |
| **8 test profiles** | ✓ | ✓ |
| **Best for** | Deep diagnostics, used PC buying | Quick checks, IT auditing |

---

## License

**Personal Use Only.** See [LICENSE](./LICENSE) for full terms.

You may flash this firmware onto your own hardware for personal use. You may **not** modify, redistribute, sell, or use it commercially.

For commercial licensing: [president@nixosoft.com](mailto:president@nixosoft.com)

---

**Built by [Nixo Soft Corporation](https://nixosoft.com)**
