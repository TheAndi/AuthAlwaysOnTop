/*
 * AuthAlwaysOnTop - keeps the Windows CredentialUIBroker prompt visible and focused.
 *
 * Copyright (C) 2025 Frog <FroggMaster@users.noreply.github.com> (original author)
 * Copyright (C) 2026 TheAndi <33332336+TheAndi@users.noreply.github.com> (modifications)
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later
 * version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 * Modified on 2026-08-28 by TheAndi; see "Changes in this fork" in
 * README.md for the full list.
 */

#ifndef WINVER
#define WINVER 0x0A00
#endif
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0A00
#endif

#define WIN32_LEAN_AND_MEAN
#define STRICT

#include <windows.h>
#include <shellapi.h>
#include <shlwapi.h>
#include <tchar.h>
#include <strsafe.h>
#include "resource.h"

#pragma comment(lib, "Shlwapi.lib")
#pragma comment(lib, "Advapi32.lib")

#define WM_TRAYICON        (WM_USER + 1)
#define WM_BROKER_DETECTED (WM_USER + 2)

#define ID_TRAY_EXIT       1001
#define ID_TRAY_TOGGLE     1002
#define ID_TRAY_HELP       1003
#define ID_TRAY_AUTOSTART  1004

#define ID_HOTKEY_TOGGLE   2001

#define TIMER_FOREGROUND   3001
#define TIMER_TRAY_RETRY   3002
#define TIMER_HOTKEY_RETRY 3003

/* The prompt is usually not visible yet when its window is created, so the
 * first attempt to foreground it regularly fails. Retry for ~3 s, then drop it. */
#define FOREGROUND_RETRY_INTERVAL_MS 150
#define FOREGROUND_RETRY_LIMIT       20

/* At logon this process is often up before Explorer has created the taskbar. */
#define TRAY_RETRY_INTERVAL_MS       1000
#define TRAY_RETRY_LIMIT             30

#define HOTKEY_RETRY_INTERVAL_MS     2000
#define HOTKEY_RETRY_LIMIT           15

#ifndef MOD_WIN
#define MOD_WIN 0x0008
#endif

static const TCHAR* const WND_CLASS_NAME  = _T("AuthAlwaysOnTopWndClass");
static const TCHAR* const MUTEX_NAME      = _T("Local\\AuthAlwaysOnTop-{9f3a5c2e-7b41-4d68-a0c5-1e8d63b47f20}");
static const TCHAR* const CONFIG_SECTION  = _T("Settings");
static const TCHAR* const CONFIG_KEY_TRAY = _T("TrayIconVisible");
static const TCHAR* const RUN_KEY         = _T("Software\\Microsoft\\Windows\\CurrentVersion\\Run");
static const TCHAR* const RUN_VALUE       = _T("AuthAlwaysOnTop");

static HINSTANCE      g_hInst          = NULL;
static HWND           g_hWndMain       = NULL;
static NOTIFYICONDATA g_nid            = { 0 };
static HWINEVENTHOOK  g_hEventHook     = NULL;
static HANDLE         g_hMutex         = NULL;
static UINT           g_taskbarCreated = 0;

static BOOL g_trayIconVisible  = TRUE;
static BOOL g_trayIconAdded    = FALSE;
static BOOL g_hotkeyRegistered = FALSE;

static TCHAR g_exePath[MAX_PATH]    = { 0 };
static TCHAR g_configPath[MAX_PATH] = { 0 };
static TCHAR g_brokerPath[MAX_PATH] = { 0 };

static HWND g_pendingBrokerWnd  = NULL;
static int  g_foregroundRetries = 0;
static int  g_trayRetries       = 0;
static int  g_hotkeyRetries     = 0;

/* ------------------------------------------------------------------------- */
/* Paths and configuration                                                    */
/* ------------------------------------------------------------------------- */

static BOOL DirectoryIsWritable(const TCHAR* dir) {
    TCHAR probe[MAX_PATH];
    if (!PathCombine(probe, dir, _T("aaot-write-probe.tmp")))
        return FALSE;

    HANDLE h = CreateFile(probe, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS,
                          FILE_ATTRIBUTE_TEMPORARY | FILE_FLAG_DELETE_ON_CLOSE, NULL);
    if (h == INVALID_HANDLE_VALUE)
        return FALSE;

    CloseHandle(h);
    return TRUE;
}

/* config.ini stays next to the executable, which is where existing installs
 * keep it. Under a read-only location such as Program Files those writes fail
 * silently and no setting survives a restart, so fall back to LOCALAPPDATA. */
static void ResolveConfigPath(void) {
    TCHAR exeDir[MAX_PATH];
    StringCchCopy(exeDir, ARRAYSIZE(exeDir), g_exePath);
    PathRemoveFileSpec(exeDir);

    if (PathCombine(g_configPath, exeDir, _T("config.ini"))) {
        if (PathFileExists(g_configPath) || DirectoryIsWritable(exeDir))
            return;
    }

    TCHAR localAppData[MAX_PATH];
    DWORD n = GetEnvironmentVariable(_T("LOCALAPPDATA"), localAppData, ARRAYSIZE(localAppData));
    if (n == 0 || n >= ARRAYSIZE(localAppData))
        return;

    TCHAR dir[MAX_PATH];
    if (!PathCombine(dir, localAppData, _T("AuthAlwaysOnTop")))
        return;

    CreateDirectory(dir, NULL);
    PathCombine(g_configPath, dir, _T("config.ini"));
}

static void LoadSettings(void) {
    g_trayIconVisible = GetPrivateProfileInt(CONFIG_SECTION, CONFIG_KEY_TRAY, 1, g_configPath) != 0;
}

static void SaveSettings(void) {
    WritePrivateProfileString(CONFIG_SECTION, CONFIG_KEY_TRAY,
                              g_trayIconVisible ? _T("1") : _T("0"), g_configPath);
}

/* ------------------------------------------------------------------------- */
/* Autostart (per-user Run key, no elevation required)                        */
/* ------------------------------------------------------------------------- */

static void BuildRunCommand(TCHAR* out, size_t cchOut) {
    StringCchPrintf(out, cchOut, _T("\"%s\""), g_exePath);
}

static BOOL GetAutostartCommand(TCHAR* out, DWORD cchOut) {
    DWORD cb = cchOut * sizeof(TCHAR);
    return RegGetValue(HKEY_CURRENT_USER, RUN_KEY, RUN_VALUE,
                       RRF_RT_REG_SZ, NULL, out, &cb) == ERROR_SUCCESS;
}

static BOOL IsAutostartEnabled(void) {
    TCHAR current[MAX_PATH + 4];
    return GetAutostartCommand(current, ARRAYSIZE(current));
}

static BOOL SetAutostart(BOOL enable) {
    HKEY hKey;
    if (RegCreateKeyEx(HKEY_CURRENT_USER, RUN_KEY, 0, NULL, 0,
                       KEY_SET_VALUE, NULL, &hKey, NULL) != ERROR_SUCCESS)
        return FALSE;

    LONG rc;
    if (enable) {
        TCHAR cmd[MAX_PATH + 4];
        BuildRunCommand(cmd, ARRAYSIZE(cmd));
        rc = RegSetValueEx(hKey, RUN_VALUE, 0, REG_SZ, (const BYTE*)cmd,
                           (DWORD)((_tcslen(cmd) + 1) * sizeof(TCHAR)));
    } else {
        rc = RegDeleteValue(hKey, RUN_VALUE);
        if (rc == ERROR_FILE_NOT_FOUND)
            rc = ERROR_SUCCESS;
    }

    RegCloseKey(hKey);
    return rc == ERROR_SUCCESS;
}

/* A Run entry left behind by an earlier location of the executable points at a
 * file that no longer exists, and autostart then fails without any diagnostic. */
static void RepairAutostartPath(void) {
    TCHAR current[MAX_PATH + 4];
    if (!GetAutostartCommand(current, ARRAYSIZE(current)))
        return;

    TCHAR expected[MAX_PATH + 4];
    BuildRunCommand(expected, ARRAYSIZE(expected));

    if (_tcsicmp(current, expected) != 0)
        SetAutostart(TRUE);
}

/* ------------------------------------------------------------------------- */
/* CredentialUIBroker detection                                               */
/* ------------------------------------------------------------------------- */

#define PID_CACHE_SIZE   16
#define PID_CACHE_TTL_MS 30000   /* bounds how long a recycled PID can be wrong */

typedef struct {
    DWORD     pid;
    ULONGLONG stamp;      /* 0 marks an unused slot */
    BOOL      isBroker;
} PidCacheEntry;

/* Only ever touched from the thread that owns the message loop: an
 * out-of-context WinEvent hook is dispatched on the installing thread. */
static PidCacheEntry g_pidCache[PID_CACHE_SIZE] = { 0 };
static int           g_pidCacheNext             = 0;

static void ResolveBrokerPath(void) {
    TCHAR winDir[MAX_PATH];
    UINT n = GetWindowsDirectory(winDir, ARRAYSIZE(winDir));
    if (n == 0 || n >= ARRAYSIZE(winDir)) {
        g_brokerPath[0] = _T('\0');
        return;
    }

    /* GetSystemDirectory would resolve to SysWOW64 in a 32-bit build, while
     * QueryFullProcessImageName always reports the real System32 path. */
    if (!PathCombine(g_brokerPath, winDir, _T("System32\\CredentialUIBroker.exe")))
        g_brokerPath[0] = _T('\0');
}

static BOOL QueryIsBrokerProcess(DWORD pid) {
    if (pid == 0 || g_brokerPath[0] == _T('\0'))
        return FALSE;

    HANDLE hProc = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (hProc == NULL)
        return FALSE;

    TCHAR imagePath[MAX_PATH];
    DWORD cch = ARRAYSIZE(imagePath);
    BOOL ok = QueryFullProcessImageName(hProc, 0, imagePath, &cch);
    CloseHandle(hProc);

    /* Comparing the full image path rather than the file name alone stops any
     * process the user can start from impersonating the broker to steal focus. */
    return ok && _tcsicmp(imagePath, g_brokerPath) == 0;
}

static BOOL IsBrokerProcess(DWORD pid) {
    ULONGLONG now = GetTickCount64();
    int slot = -1;

    for (int i = 0; i < PID_CACHE_SIZE; ++i) {
        if (g_pidCache[i].stamp != 0 && g_pidCache[i].pid == pid) {
            if (now - g_pidCache[i].stamp < PID_CACHE_TTL_MS)
                return g_pidCache[i].isBroker;
            slot = i;      /* stale entry for this PID, refresh it in place */
            break;
        }
    }

    if (slot < 0) {
        slot = g_pidCacheNext;
        g_pidCacheNext = (g_pidCacheNext + 1) % PID_CACHE_SIZE;
    }

    BOOL isBroker = QueryIsBrokerProcess(pid);
    g_pidCache[slot].pid      = pid;
    g_pidCache[slot].stamp    = now;
    g_pidCache[slot].isBroker = isBroker;
    return isBroker;
}

/* ------------------------------------------------------------------------- */
/* Foreground handoff                                                         */
/* ------------------------------------------------------------------------- */

/* Windows only lets the foreground process give focus away. Dropping the
 * foreground lock timeout for the duration of the call is enough, and unlike
 * the widespread SendInput() trick it injects no keystrokes into whatever
 * window the user happens to be typing in. */
static void ClearForegroundLock(DWORD* savedTimeout, BOOL* restore) {
    *restore      = FALSE;
    *savedTimeout = 0;

    if (!SystemParametersInfo(SPI_GETFOREGROUNDLOCKTIMEOUT, 0, savedTimeout, 0))
        return;
    if (*savedTimeout == 0)
        return;

    if (SystemParametersInfo(SPI_SETFOREGROUNDLOCKTIMEOUT, 0, (PVOID)0, SPIF_SENDCHANGE))
        *restore = TRUE;
}

static void RestoreForegroundLock(DWORD savedTimeout, BOOL restore) {
    if (restore)
        SystemParametersInfo(SPI_SETFOREGROUNDLOCKTIMEOUT, 0,
                             (PVOID)(UINT_PTR)savedTimeout, SPIF_SENDCHANGE);
}

/* Returns TRUE once nothing further is worth attempting for this window. */
static BOOL ForceToForeground(HWND hwnd) {
    if (!IsWindow(hwnd))
        return TRUE;
    if (GetForegroundWindow() == hwnd)
        return TRUE;
    if (!IsWindowVisible(hwnd))
        return FALSE;      /* created but not shown yet - let the timer retry */

    DWORD targetThread  = GetWindowThreadProcessId(hwnd, NULL);
    DWORD currentThread = GetCurrentThreadId();
    BOOL  attached      = FALSE;

    if (targetThread != 0 && targetThread != currentThread)
        attached = AttachThreadInput(currentThread, targetThread, TRUE);

    if (IsIconic(hwnd))
        ShowWindow(hwnd, SW_RESTORE);

    /* The prompt stays topmost for the rest of its life. The original toggled
     * HWND_TOPMOST straight back to HWND_NOTOPMOST, which undid the effect the
     * moment it was applied. */
    SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);

    BOOL ok = SetForegroundWindow(hwnd);
    if (!ok) {
        DWORD savedTimeout;
        BOOL  restore;
        ClearForegroundLock(&savedTimeout, &restore);
        ok = SetForegroundWindow(hwnd);
        RestoreForegroundLock(savedTimeout, restore);
    }

    if (ok) {
        BringWindowToTop(hwnd);
        SetActiveWindow(hwnd);
        SetFocus(hwnd);
    }

    if (attached)
        AttachThreadInput(currentThread, targetThread, FALSE);

    return ok || GetForegroundWindow() == hwnd;
}

static void CALLBACK WinEventProc(HWINEVENTHOOK hHook, DWORD event, HWND hwnd,
                                  LONG idObject, LONG idChild,
                                  DWORD idEventThread, DWORD dwmsEventTime) {
    UNREFERENCED_PARAMETER(hHook);
    UNREFERENCED_PARAMETER(event);
    UNREFERENCED_PARAMETER(idEventThread);
    UNREFERENCED_PARAMETER(dwmsEventTime);

    /* EVENT_OBJECT_CREATE fires for carets, menu items, list entries and every
     * other accessible object in every process on the desktop - hundreds of
     * times per second on a busy machine. Rejecting everything that is not a
     * top-level window before touching the process list is what keeps this
     * hook off the CPU. */
    if (hwnd == NULL || idObject != OBJID_WINDOW || idChild != CHILDID_SELF)
        return;
    if (GetAncestor(hwnd, GA_PARENT) != GetDesktopWindow())
        return;

    DWORD pid = 0;
    GetWindowThreadProcessId(hwnd, &pid);
    if (!IsBrokerProcess(pid))
        return;

#ifdef _DEBUG
    OutputDebugString(_T("AuthAlwaysOnTop: CredentialUIBroker window detected.\n"));
#endif

    /* Hand the work to the message loop so the foreground dance never stalls
     * delivery of further accessibility events. */
    PostMessage(g_hWndMain, WM_BROKER_DETECTED, (WPARAM)hwnd, 0);
}

/* ------------------------------------------------------------------------- */
/* Tray icon and hotkey                                                       */
/* ------------------------------------------------------------------------- */

static BOOL AddTrayIcon(HWND hwnd) {
    if (g_trayIconAdded)
        return TRUE;

    ZeroMemory(&g_nid, sizeof(g_nid));
    g_nid.cbSize           = sizeof(g_nid);
    g_nid.hWnd             = hwnd;
    g_nid.uID              = 1;
    g_nid.uFlags           = NIF_ICON | NIF_MESSAGE | NIF_TIP;
    g_nid.uCallbackMessage = WM_TRAYICON;
    g_nid.hIcon            = LoadIcon(g_hInst, MAKEINTRESOURCE(IDI_ICON5));
    StringCchCopy(g_nid.szTip, ARRAYSIZE(g_nid.szTip), _T("AuthAlwaysOnTop"));

    g_trayIconAdded = Shell_NotifyIcon(NIM_ADD, &g_nid);
    return g_trayIconAdded;
}

static void RemoveTrayIcon(void) {
    if (!g_trayIconAdded)
        return;

    Shell_NotifyIcon(NIM_DELETE, &g_nid);
    g_trayIconAdded = FALSE;
}

static void SetTrayIconVisible(HWND hwnd, BOOL visible) {
    g_trayIconVisible = visible;

    if (visible) {
        if (!AddTrayIcon(hwnd)) {
            g_trayRetries = 0;
            SetTimer(hwnd, TIMER_TRAY_RETRY, TRAY_RETRY_INTERVAL_MS, NULL);
        }
    } else {
        RemoveTrayIcon();
    }

    SaveSettings();
}

/* Right after logon another process may still own the combination. */
static BOOL TryRegisterHotkey(HWND hwnd) {
    if (g_hotkeyRegistered)
        return TRUE;

    g_hotkeyRegistered = RegisterHotKey(hwnd, ID_HOTKEY_TOGGLE,
                                        MOD_CONTROL | MOD_WIN | MOD_ALT | MOD_NOREPEAT,
                                        VK_SCROLL);
    return g_hotkeyRegistered;
}

static void ShowTrayMenu(HWND hwnd) {
    POINT pt;
    GetCursorPos(&pt);

    HMENU hMenu = CreatePopupMenu();
    if (hMenu == NULL)
        return;

    AppendMenu(hMenu, MF_STRING | (IsAutostartEnabled() ? MF_CHECKED : MF_UNCHECKED),
               ID_TRAY_AUTOSTART, _T("Start with Windows"));
    AppendMenu(hMenu, MF_SEPARATOR, 0, NULL);
    AppendMenu(hMenu, MF_STRING, ID_TRAY_TOGGLE,
               g_trayIconVisible ? _T("Hide Tray Icon") : _T("Show Tray Icon"));
    AppendMenu(hMenu, MF_STRING, ID_TRAY_HELP, _T("Help"));
    AppendMenu(hMenu, MF_SEPARATOR, 0, NULL);
    AppendMenu(hMenu, MF_STRING, ID_TRAY_EXIT, _T("Exit"));

    SetForegroundWindow(hwnd);
    TrackPopupMenu(hMenu, TPM_RIGHTBUTTON | TPM_BOTTOMALIGN, pt.x, pt.y, 0, hwnd, NULL);
    PostMessage(hwnd, WM_NULL, 0, 0);

    DestroyMenu(hMenu);
}

static void Cleanup(HWND hwnd) {
    KillTimer(hwnd, TIMER_FOREGROUND);
    KillTimer(hwnd, TIMER_TRAY_RETRY);
    KillTimer(hwnd, TIMER_HOTKEY_RETRY);

    RemoveTrayIcon();

    if (g_hEventHook) {
        UnhookWinEvent(g_hEventHook);
        g_hEventHook = NULL;
    }
    if (g_hotkeyRegistered) {
        UnregisterHotKey(hwnd, ID_HOTKEY_TOGGLE);
        g_hotkeyRegistered = FALSE;
    }
}

static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
    case WM_TRAYICON:
        if (lParam == WM_RBUTTONUP)
            ShowTrayMenu(hwnd);
        break;

    case WM_COMMAND:
        switch (LOWORD(wParam)) {
        case ID_TRAY_AUTOSTART:
            if (!SetAutostart(!IsAutostartEnabled())) {
                MessageBox(hwnd,
                    _T("Could not update the autostart entry under\n")
                    _T("HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run."),
                    _T("AuthAlwaysOnTop"), MB_OK | MB_ICONWARNING);
            }
            break;

        case ID_TRAY_TOGGLE:
            SetTrayIconVisible(hwnd, !g_trayIconVisible);
            break;

        case ID_TRAY_HELP:
            MessageBox(hwnd,
                _T("AuthAlwaysOnTop Help\n\n")
                _T("The Windows credential prompt is brought to the front and kept ")
                _T("on top as soon as it appears.\n\n")
                _T("Hotkey: Ctrl + Win + Alt + ScrollLock\n")
                _T("Toggles the tray icon at any time.\n\n")
                _T("\"Start with Windows\" registers this executable for the current ")
                _T("user only; no administrator rights are needed. Moving the ")
                _T("executable is picked up automatically on the next start.\n\n")
                _T("Tray icon visibility is also stored in config.ini next to the ")
                _T("executable."),
                _T("Help"), MB_OK | MB_ICONINFORMATION);
            break;

        case ID_TRAY_EXIT:
            DestroyWindow(hwnd);
            break;
        }
        break;

    case WM_HOTKEY:
        if (wParam == ID_HOTKEY_TOGGLE)
            SetTrayIconVisible(hwnd, !g_trayIconVisible);
        break;

    case WM_BROKER_DETECTED:
        g_pendingBrokerWnd  = (HWND)wParam;
        g_foregroundRetries = 0;
        if (ForceToForeground(g_pendingBrokerWnd)) {
            KillTimer(hwnd, TIMER_FOREGROUND);
            g_pendingBrokerWnd = NULL;
        } else {
            SetTimer(hwnd, TIMER_FOREGROUND, FOREGROUND_RETRY_INTERVAL_MS, NULL);
        }
        break;

    case WM_TIMER:
        switch (wParam) {
        case TIMER_FOREGROUND:
            if (g_pendingBrokerWnd == NULL ||
                ForceToForeground(g_pendingBrokerWnd) ||
                ++g_foregroundRetries >= FOREGROUND_RETRY_LIMIT) {
                KillTimer(hwnd, TIMER_FOREGROUND);
                g_pendingBrokerWnd = NULL;
            }
            break;

        case TIMER_TRAY_RETRY:
            if (!g_trayIconVisible || AddTrayIcon(hwnd) ||
                ++g_trayRetries >= TRAY_RETRY_LIMIT) {
                KillTimer(hwnd, TIMER_TRAY_RETRY);
            }
            break;

        case TIMER_HOTKEY_RETRY:
            if (TryRegisterHotkey(hwnd) || ++g_hotkeyRetries >= HOTKEY_RETRY_LIMIT)
                KillTimer(hwnd, TIMER_HOTKEY_RETRY);
            break;
        }
        break;

    case WM_ENDSESSION:
        /* Logging off without this leaves a ghost icon in the tray. */
        if (wParam)
            RemoveTrayIcon();
        break;

    case WM_DESTROY:
        Cleanup(hwnd);
        PostQuitMessage(0);
        break;

    default:
        if (g_taskbarCreated != 0 && msg == g_taskbarCreated) {
            /* Explorer has (re)started and dropped every tray icon it knew. */
            g_trayIconAdded = FALSE;
            if (g_trayIconVisible)
                AddTrayIcon(hwnd);
            return 0;
        }
        return DefWindowProc(hwnd, msg, wParam, lParam);
    }

    return 0;
}

int APIENTRY WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nCmdShow) {
    UNREFERENCED_PARAMETER(hPrevInstance);
    UNREFERENCED_PARAMETER(lpCmdLine);
    UNREFERENCED_PARAMETER(nCmdShow);

    g_hInst = hInstance;

    DWORD n = GetModuleFileName(NULL, g_exePath, ARRAYSIZE(g_exePath));
    if (n == 0 || n >= ARRAYSIZE(g_exePath))
        return 1;

    /* The original single-instance check exited whenever the mutex name was
     * taken, so any process running as the same user could squat the name and
     * block startup for good - silently, because the notice was commented out.
     * An existing instance now has to prove itself with a window. */
    g_hMutex = CreateMutex(NULL, FALSE, MUTEX_NAME);
    BOOL mutexHeld = (g_hMutex != NULL && GetLastError() != ERROR_ALREADY_EXISTS);

    if (!mutexHeld) {
        for (int i = 0; i < 10; ++i) {
            if (FindWindow(WND_CLASS_NAME, NULL) != NULL) {
                if (g_hMutex)
                    CloseHandle(g_hMutex);
                return 0;
            }
            Sleep(50);   /* give a genuine instance a moment to show its window */
        }
    }

    ResolveConfigPath();
    ResolveBrokerPath();
    LoadSettings();
    RepairAutostartPath();

    g_taskbarCreated = RegisterWindowMessage(_T("TaskbarCreated"));

    WNDCLASS wc = { 0 };
    wc.lpfnWndProc   = WndProc;
    wc.hInstance     = hInstance;
    wc.lpszClassName = WND_CLASS_NAME;
    wc.hCursor       = LoadCursor(NULL, IDC_ARROW);
    if (!RegisterClass(&wc))
        return 1;

    g_hWndMain = CreateWindowEx(0, WND_CLASS_NAME, _T("AuthAlwaysOnTop"), WS_POPUP,
                                CW_USEDEFAULT, CW_USEDEFAULT, 0, 0,
                                NULL, NULL, hInstance, NULL);
    if (g_hWndMain == NULL)
        return 1;

    /* Explorer broadcasts TaskbarCreated at its own integrity level; without
     * this filter an elevated instance never receives it. */
    if (g_taskbarCreated != 0)
        ChangeWindowMessageFilterEx(g_hWndMain, g_taskbarCreated, MSGFLT_ALLOW, NULL);

    if (g_trayIconVisible && !AddTrayIcon(g_hWndMain))
        SetTimer(g_hWndMain, TIMER_TRAY_RETRY, TRAY_RETRY_INTERVAL_MS, NULL);

    if (!TryRegisterHotkey(g_hWndMain))
        SetTimer(g_hWndMain, TIMER_HOTKEY_RETRY, HOTKEY_RETRY_INTERVAL_MS, NULL);

    g_hEventHook = SetWinEventHook(EVENT_OBJECT_CREATE, EVENT_OBJECT_CREATE,
                                   NULL, WinEventProc, 0, 0,
                                   WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS);
    if (g_hEventHook == NULL) {
        MessageBox(NULL, _T("Could not install the window event hook; the credential ")
                         _T("prompt will not be detected."),
                   _T("AuthAlwaysOnTop"), MB_OK | MB_ICONERROR);
        DestroyWindow(g_hWndMain);
        if (g_hMutex)
            CloseHandle(g_hMutex);
        return 1;
    }

    MSG msg;
    BOOL ret;
    while ((ret = GetMessage(&msg, NULL, 0, 0)) != 0) {
        if (ret == -1)
            break;
        TranslateMessage(&msg);
        DispatchMessage(&msg);
    }

    if (g_hMutex)
        CloseHandle(g_hMutex);

    return 0;
}
