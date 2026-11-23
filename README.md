# ScreenBoard

A SwiftUI app for macOS 26 or later, built with Liquid Glass, that locks input devices so you can clean them.

Select any combination of **Keyboard**, **Screen** and **Trackpad**, then press
**Start**, or use **Deep Clean** to lock all three. The selected devices lock
immediately and the others keep working.

Screen cleaning appears only on Macs with a touch display, meaning a HID
device that reports the Digitizer › Touch Screen usage. The app checks again
whenever displays change. Other Macs offer Keyboard and Trackpad only.

| Device | When locked |
|---|---|
| Keyboard | All keys do nothing, including media keys |
| Screen | A black full-screen shield covers every display; touch, clicks and gestures are blocked; the Dock, menu bar and app switching are disabled |
| Trackpad | The cursor is frozen; clicks, scrolling and gestures are blocked |

Press Esc three times in a row within 1.5 s to unlock everything, even when the
keyboard itself is locked. On-screen dots show each press. A failsafe always
unlocks after 1, 3, 5 or 10 minutes (3 by default). The app also unlocks on
sleep, display sleep, a user switch, Accessibility being revoked, Secure Input
turning on, or the input blocker dying. Your last selection is remembered.

## Build

```sh
./scripts/build-app.sh                 # ad-hoc signed build/ScreenBoard.app
SIGN_IDENTITY="Developer ID Application: …" ./scripts/build-app.sh
```

This needs only the Command Line Tools. You can open `Package.swift` in Xcode
too. The app can't be sandboxed, because CGEventTap needs that.

## Permissions

Grant **System Settings › Privacy & Security › Accessibility**. An ad-hoc
signature changes on every rebuild, so macOS drops the grant each time. Sign
with a stable identity to keep it.

## Known limits

- Power/Touch ID, the lid, and some Globe/Fn handling can't be blocked.
- If Secure Input is on (a focused password field, or Terminal's Secure
  Keyboard Entry), event taps see no keys. The app refuses to start, or stops
  the keyboard lock.
- Locking the screen drops every pointer-class event at the HID tap, so the
  trackpad doesn't work during screen cleaning either. Once the touch event subtype is
  known on real hardware, the tap can drop only touches.
