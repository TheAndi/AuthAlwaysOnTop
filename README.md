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

### Icon

`AuthAlwaysOnTop/AuthAlwaysOnTop.ico` is original artwork, Copyright (C) 2026 TheAndi, covered by the same GPL-3.0-or-later license as the rest of the project.

It is not hand-drawn in an editor but generated from geometric primitives by [tools/make-icon.ps1](tools/make-icon.ps1), so the provenance is reproducible rather than asserted — run the script and you get the identical file. It depends on nothing but GDI+ and contains no third-party artwork.

The mark sets the application's initials out as a face — `A` and `T` for the eyes, `O` for the mouth:

```
A   T
  O
```

Notification area sizes carry no background tile and are drawn as a blue glyph on nothing, which is how the rest of the tray looks; the rounded tile only appears from 40 px upwards, where Explorer and the file properties dialog use it.

Letterforms and a face are both generic; nothing here is traced or reproduced from any vendor's logo, wordmark or icon set.

This replaces the icon inherited from upstream, whose origin and license could not be established.

# Changes in this fork

This is a modified version of [FroggMaster/AuthAlwaysOnTop](https://github.com/FroggMaster/AuthAlwaysOnTop). Modified on 2026-08-28 by TheAndi:

**CPU usage**

- Process identification no longer takes a full `CreateToolhelp32Snapshot` of the system per event. That snapshot ran for every accessible object created anywhere on the desktop — carets, menu items, list entries included — and is where the CPU went. It now resolves the image path of a single process and caches the verdict per PID with a 30 second expiry. Measured on an idle desktop, that is the difference between 97.5% and 0.3% of a core.
- The hook deliberately does **not** filter events by object type or window ancestry. Rejecting all but top-level `OBJID_WINDOW` events looks like the obvious further saving, but the credential prompt does not reliably present itself that way and the tool then matches nothing at all. The per-PID cache is what makes the hook cheap.

**Security**

- The credential broker is now identified by its full image path under `%SystemRoot%\System32`, not by file name alone, so no user-startable process can impersonate it to grab focus.
- The foreground handoff no longer opens by injecting synthetic keystrokes. It tries a plain handoff first, then briefly clears the foreground lock timeout, and only if both fail does it fall back to a single inert `Ctrl` press. The original sent `Shift` every time, which feeds the StickyKeys counter and lands in whatever window currently has focus.
- The single-instance mutex uses an unguessable name and an existing instance now has to prove itself with a window, so a squatted mutex can no longer block startup silently.
- Control Flow Guard, `/Qspectre`, `/CETCOMPAT`, `/SAFESEH`, DEP and ASLR are enabled explicitly, and the executable carries a version resource and an application manifest (`asInvoker`, per-monitor DPI).
- CI actions are pinned to commit SHAs and checkout no longer persists credentials.

**Reliability**

- The tray icon is restored when Explorer restarts and is retried at startup, which is what made autostart look like it had failed at logon.
- Hotkey registration is retried when another application holds the combination at logon.
- Built-in per-user autostart with a self-repairing path.
- The prompt now actually stays topmost; `HWND_TOPMOST` was previously reset to `HWND_NOTOPMOST` in the same call, undoing the effect.
- Foregrounding is retried for ~3 seconds, because the prompt is frequently not ready at the moment its window is created.
- `config.ini` falls back to `%LOCALAPPDATA%` when the install directory is read-only, where writes used to fail silently.
- The tray icon is removed on logoff instead of leaving a ghost behind.

**Artwork**

- Replaced the application icon with original artwork generated by [tools/make-icon.ps1](tools/make-icon.ps1) — the initials A, O and T arranged as a face. The inherited icon had no traceable origin or license.
- The notification area icon is loaded with `LoadImage` at `SM_CXSMICON` rather than `LoadIcon`. `LoadIcon` only ever returns the 32 px image and leaves the shell to shrink it, which never used the separately drawn 16 px variant.
