# ScreenBoard

A small Mac app that stops your keyboard, trackpad and screen from reacting
while you wipe them clean. It needs macOS 26 or later.

## How to use it

1. Turn on the parts you want to clean: **Keyboard**, **Trackpad**, and
   **Screen** if your Mac has a touchscreen. You can also click them in the
   picture of the Mac. Keyboard is on the first time you open the app.
2. Click **Start Cleaning**, or **Lock All** to lock everything at once.
3. Wipe away. The parts you didn't pick keep working as usual.
4. When you're done, press **Esc three times** quickly. This works even while
   the keyboard is locked. The three `esc` keys in the window light up as you
   press.

If you forget, the app unlocks by itself after a few minutes. You pick 1, 3,
5 or 10 minutes, and 3 is the default.

## What "locked" means

| Part | While it's locked |
|---|---|
| Keyboard | No key does anything, not even volume or brightness. |
| Trackpad | The pointer stays where it is, and clicks, scrolling and gestures do nothing. |
| Screen | Every display goes black so smudges are easy to see. Touches and clicks do nothing, and the Dock, menu bar and app switching are turned off. |

The Screen option only shows up on Macs with a touchscreen. If you plug in a
touch monitor while the app is open, it appears.

For safety, the app also unlocks on its own if the Mac goes to sleep, you
switch users, or something stops it from blocking input properly.

## First launch: allow access

macOS only lets an app block input if you allow it. Click **Open Privacy
Settings…** in the app. System Settings opens with a small window underneath
that holds the ScreenBoard icon. Drag that icon into the list of apps, then
turn on its switch. ScreenBoard comes back to the front once access is on.

## Build it yourself

```sh
./scripts/build-app.sh
```

This creates `build/ScreenBoard.app`. You only need Apple's Command Line
Tools, not full Xcode, but you can still open `Package.swift` in Xcode if you
like.

Each rebuild gets a new temporary signature, so macOS forgets the permission
and you'll have to allow access again. To avoid that, sign with your own
Developer ID:

```sh
SIGN_IDENTITY="Developer ID Application: …" ./scripts/build-app.sh
```

The app can't run in Apple's sandbox, because blocking input isn't allowed
from inside it.

## What it can't block

- The power button, Touch ID, and closing the lid.
- Some presses of the Globe/Fn key.
- Typing in a password field, or using Terminal with Secure Keyboard Entry
  on. macOS hides keystrokes from other apps then, so ScreenBoard won't start
  a keyboard lock, and it stops one that's already running.
- Locking the screen also locks the trackpad, because for now the app can't
  tell a screen touch apart from a trackpad touch.
