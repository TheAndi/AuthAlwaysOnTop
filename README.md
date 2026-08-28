# AuthAlwaysOnTop

A lightweight utility that keeps the Windows **CredentialUIBroker** prompt always visible and in focus. It detects the window, brings it to the foreground, and ensures it stays on top, preventing it from getting hidden behind other windows during credential prompts.

Created out of necessity for browser extensions like **Bitwarden**, which cannot authoritatively bring the Windows authentication window to the front.

# Usage

Simply run `AuthAlwaysOnTop.exe`. The application will run silently in the background and monitor for the Windows **CredentialUIBroker** dialog. When detected, the utility will automatically:

- Bring the prompt window to the front.
- Force focus and top-most status, even if other applications attempt to cover it.
- Restore it from a minimized state if needed.

### Tray Icon

By default, the app displays a tray icon for quick access:

- **Right-click** the tray icon to:
  - Toggle **Start with Windows**.
  - Hide or show the tray icon.
  - View help.
  - Exit the application.

Tray icon visibility is persisted via a `config.ini` file stored in the same folder as the executable.

### Autostart

Enable **Start with Windows** from the tray menu. This registers the executable under
`HKCU\Software\Microsoft\Windows\CurrentVersion\Run` for the current user only — no administrator rights are required, and nothing is written outside your own profile.

Moving or renaming the executable does not break autostart: the stored path is checked on every start and rewritten when it no longer matches.

If the tray icon does not appear right after logon, the app is still running. It re-registers with the notification area as soon as Explorer announces the taskbar, and keeps retrying for about 30 seconds, so no manual restart is needed.

### Hotkey

A global hotkey is registered to toggle the tray icon:

**`Ctrl + Win + Alt + Scroll Lock`**

Use this hotkey to show or hide the tray icon at any time. If another application already owns the combination at logon, registration is retried for about half a minute.

### Configuration

A `config.ini` file will be created automatically alongside the executable the first time you toggle the tray icon.

If the executable lives in a location you cannot write to (for example `C:\Program Files`), the file is created under `%LOCALAPPDATA%\AuthAlwaysOnTop\config.ini` instead, so settings still survive a restart.

below is an example `config.ini`:

```ini
[Settings]
; TrayIconVisible determines whether the system tray icon is shown on launch. (use hotkey to toggle: Ctrl + Win + Alt + Scroll Lock)
; 1 = Show tray icon (default)
; 0 = Hide tray icon
TrayIconVisible=1
```

# Building

Open `AuthAlwaysOnTop.sln` in Visual Studio 2022 (toolset v143) and build the `Release` configuration, or from a developer prompt:

```
msbuild AuthAlwaysOnTop.sln /p:Configuration=Release /p:Platform=x64
```

`Release` and `Debug` are available for both `x64` and `Win32`. CI builds both platforms on every push.

# License

This program is free software, licensed under the **GNU General Public License v3.0 or later**. See [LICENSE](LICENSE) for the full text.

Original work Copyright (C) 2025 Frog ([FroggMaster/AuthAlwaysOnTop](https://github.com/FroggMaster/AuthAlwaysOnTop)).
Modifications Copyright (C) 2026 TheAndi.

# Changes in this fork

This is a modified version of [FroggMaster/AuthAlwaysOnTop](https://github.com/FroggMaster/AuthAlwaysOnTop). Modified on 2026-08-28 by TheAndi:

**CPU usage**

- The system-wide `EVENT_OBJECT_CREATE` hook now discards everything that is not a top-level window before doing any further work. Previously every accessible object created anywhere on the desktop — carets, menu items, list entries — was inspected.
- Process identification no longer takes a full `CreateToolhelp32Snapshot` of the system per event. It resolves the image path of a single process instead, and caches the verdict per PID with a 30 second expiry.

**Security**

- The credential broker is now identified by its full image path under `%SystemRoot%\System32`, not by file name alone, so no user-startable process can impersonate it to grab focus.
- The foreground handoff no longer injects synthetic `SendInput` keystrokes into whatever window currently has focus. It briefly clears the foreground lock timeout instead.
- The single-instance mutex uses an unguessable name and an existing instance now has to prove itself with a window, so a squatted mutex can no longer block startup silently.
- Control Flow Guard, `/Qspectre`, `/CETCOMPAT`, `/SAFESEH`, DEP and ASLR are enabled explicitly, and the executable carries a version resource and an application manifest (`asInvoker`, per-monitor DPI).
- CI actions are pinned to commit SHAs and checkout no longer persists credentials.

**Reliability**

- The tray icon is restored when Explorer restarts and is retried at startup, which is what made autostart look like it had failed at logon.
- Hotkey registration is retried when another application holds the combination at logon.
- Built-in per-user autostart with a self-repairing path.
- The prompt now actually stays topmost; `HWND_TOPMOST` was previously reset to `HWND_NOTOPMOST` in the same call, undoing the effect.
- Foregrounding is retried for ~3 seconds, because the prompt window is frequently not visible yet at the moment it is created.
- `config.ini` falls back to `%LOCALAPPDATA%` when the install directory is read-only, where writes used to fail silently.
- The tray icon is removed on logoff instead of leaving a ghost behind.
