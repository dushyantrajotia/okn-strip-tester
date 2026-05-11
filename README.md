# OKN Strip Tester

Two-part binocular vision testing system:

- `android-app/`: Flutter phone display app for VR headset use (left/right eye split rendering)
- `laptop-controller/`: Node.js WebSocket hub + browser control panel

## 1) Laptop Controller Setup

From `laptop-controller/`:

```bash
npm install
npm start
```

Then open:

- `http://localhost:8080`

The page contains:

- Connection status indicator (`Phone: Connected/Disconnected`)
- Global controls: Start Both, Stop Both, Sync Mode
- Per-eye controls (left/right): width, speed, contrast, colors, direction, start/stop

## 2) Android App Setup (Flutter)

This repository includes the core Flutter source (`lib/main.dart`) and manifest orientation lock. If Flutter is not already initialized in `android-app/`, run this from `android-app/` on a machine with Flutter installed:

```bash
flutter create .
```

After that command, keep/restore these files from this repo if overwritten:

- `android-app/lib/main.dart`
- `android-app/pubspec.yaml`
- `android-app/android/app/src/main/AndroidManifest.xml`

Install dependency and run:

```bash
flutter pub get
flutter run
```

## 3) Connect Phone to Laptop

1. Put laptop and Android phone on the same Wi-Fi network.
2. Start laptop server (`npm start`).
3. Find laptop IP address (for example `192.168.1.10`).
4. On phone app, tap `CONNECT` and enter:
   - `ws://<laptop-ip>:8080`
5. In browser controller, set host/IP if needed and click `Reconnect Panel`.
6. When controller shows `Phone: Connected`, start testing.

## WebSocket Command Protocol

Controller sends command payloads through the server to phone:

```json
{ "action": "start", "eye": "left" }
{ "action": "start", "eye": "right" }
{ "action": "start", "eye": "both" }
{ "action": "stop", "eye": "left" }
{
  "action": "update",
  "eye": "left",
  "params": {
    "widthMm": 11.5,
    "speedLevel": 5,
    "contrastLevel": 3,
    "stripColor": "#FF0000",
    "bgColor": "#000000",
    "direction": "rtl"
  }
}
```

Phone sends ACK (forwarded to controller log panel):

```json
{ "status": "ok", "eye": "left" }
```

## Vision-Display Behavior Implemented

- Landscape-locked display
- Fullscreen immersive mode
- Left/right independent halves with black center divider
- Canvas-rendered animated vertical stripes (no image assets)
- Runtime parameter updates mid-animation via WebSocket
- Independent or combined control for both eyes
- mm to px conversion using DPI (`px = (mm / 25.4) * dpi`)
- Contrast reduction by blending strip color toward background
- Optional on-device 10mm calibration reference dialog

## Notes

- The controller server accepts one active phone display session at a time.
- The browser panel can be opened on the laptop itself or another device on the same LAN.
- Local network only, internet not required.
