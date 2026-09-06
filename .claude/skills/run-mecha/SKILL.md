---
name: run-mecha
description: Launch and drive the Mecha POC (Godot 4.7.2 desktop game) on Windows — start the app, capture the window even when it is occluded, click through the loadout screen into a battle, and run the GUT test suite headless. Use when asked to run, start, screenshot, or manually verify the game.
---

# Running the Mecha POC

Godot 4.7.2 tactical-mecha prototype. `project.godot` at the repo root, main
scene `res://run/main.tscn` → `GameFlow` (Squad Loadout → Deploy → Battle).

## Godot binary

Installed, not on `PATH`:

- `C:\Program Files\Godot\Godot_v4.7.2-stable_win64_console.exe` — **use this
  one**; it prints engine/script output to stdout.
- `C:\Program Files\Godot\Godot_v4.7.2-stable_win64.exe` — no console.

From the Bash tool, quote the path: `"/c/Program Files/Godot/Godot_v4.7.2-stable_win64_console.exe"`.

## Run the test suite (do this first for any code change)

```bash
cd "/f/Repos/Godot/4.7.2/mecha" && \
"/c/Program Files/Godot/Godot_v4.7.2-stable_win64_console.exe" \
  --path "F:\Repos\Godot\4.7.2\mecha" -s addons/gut/gut_cmdln.gd -gexit 2>&1 \
  | grep -vE "SHA256|Shader " | tail -20
```

Config lives in `.gutconfig.json` (`tests/unit` + `tests/integration`,
`include_subdirs`). Run one file with `-gtest=res://tests/integration/<file>.gd`.
A clean run ends with `---- All tests passed! ----`; the suite is ~180+ tests in
~10 s. GUT prints a lot of shader-hash noise — the `grep -vE` above drops it.

## Launch the game

```bash
"/c/Program Files/Godot/Godot_v4.7.2-stable_win64_console.exe" \
  --path "F:\Repos\Godot\4.7.2\mecha" > /tmp/mecha.log 2>&1 &
```

Run it backgrounded. The `_console.exe` process exits almost immediately after
spawning the real game process (`Godot_v4.7.2-stable_win64.exe`), so **the
backgrounded command "completing" does not mean the game closed** — check for the
real process:

```bash
tasklist //FI "IMAGENAME eq Godot_v4.7.2-stable_win64.exe" 2>&1 | grep win64
```

The game window title is **`Mecha (DEBUG)`**. A live game process sits around
180 MB; ~7 MB is just the console stub.

Dev shortcut — skip the loadout screen and drop straight into a mission with the
baseline squad (handy for screenshotting the battle without clicking DEPLOY):

```bash
"/c/Program Files/Godot/Godot_v4.7.2-stable_win64_console.exe" \
  --path "F:\Repos\Godot\4.7.2\mecha" -- battle
# or a specific mission:  -- battle the_chokepoint
```

Headless-ish smoke test (boots, runs N frames, exits 0, prints any script error):

```bash
"/c/Program Files/Godot/Godot_v4.7.2-stable_win64_console.exe" \
  --path "F:\Repos\Godot\4.7.2\mecha" --quit-after 240 2>&1 | grep -viE "SHA256|Shader "
```

## Screenshot the window (works even when it is behind other windows)

`CopyFromScreen` grabs whatever is on top, and Windows blocks
`SetForegroundWindow` from a background script — so **use `PrintWindow` with
`PW_RENDERFULLCONTENT` (flag `2`)** to capture the game window directly.

```powershell
$p = Get-Process | Where-Object { $_.MainWindowTitle -eq "Mecha (DEBUG)" } | Select-Object -First 1
Add-Type @"
using System; using System.Runtime.InteropServices;
public class PW {
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint f);
  public struct RECT { public int Left, Top, Right, Bottom; }
}
"@ -ReferencedAssemblies System.Drawing
$h = $p.MainWindowHandle
$r = New-Object PW+RECT; [void][PW]::GetWindowRect($h, [ref]$r)
$w = $r.Right - $r.Left; $ht = $r.Bottom - $r.Top
Add-Type -AssemblyName System.Drawing
$bmp = New-Object System.Drawing.Bitmap($w, $ht)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc(); [void][PW]::PrintWindow($h, $hdc, 2); $g.ReleaseHdc($hdc)
$bmp.Save("$env:TEMP\mecha_shot.png", [System.Drawing.Imaging.ImageFormat]::Png)
"$env:TEMP\mecha_shot.png"
```

Then `Read` the PNG. **Always look at it** — a blank/dark frame means the game
failed to reach the screen you expected.

## Drive it

Clicks reach Godot **only while the window is foreground**, and Windows only lets
a script foreground a window in the same call that then acts. So do
foreground + settle + click in **one** PowerShell block:
`SetWindowPos(HWND_TOP, SWP_NOMOVE|SWP_NOSIZE|SWP_SHOWWINDOW)` →
`SetForegroundWindow` → `Start-Sleep 1800` → `SetCursorPos` +
`mouse_event 0x0002` / `0x0004`. Screenshot in a **separate** call (a PrintWindow
taken <~1 s after a foreground change comes back black).

Screen coords = window `GetWindowRect().Left/Top` + the pixel offset read off the
PrintWindow screenshot (the capture includes the ~8 px border / ~31 px title
bar; with the window at `-8,-31` the two offsets cancel and screenshot pixel ≈
screen coord).

Large HUD/Control targets click reliably: loadout roster tabs and option cards,
battle **squad-rail tiles** (top-right) and **action-bar cards** (bottom-centre),
End Turn / Restart / Loadout. To select a mech in battle, click its rail tile,
not the board sprite. Individual isometric grid tiles have been flaky to hit via
automation — for "move a mech, run the enemy turn" paths, trust
`tests/integration/test_isometric_view.gd`, which drives them through
`_unhandled_input`. Don't burn more than ~3 attempts on a grid click.

Typical first drive: launch → screenshot the **Squad Loadout** screen → click
**DEPLOY** (bottom strip) → screenshot the **battle** (isometric board + right-
hand HUD; "TURN 1 / 5", squad list, End Turn / Restart Mission / Return to
Loadout).

In battle: left-click a mech to select, click a blue tile to move, number keys
1–4 pick abilities, `M` move, `Enter` ends turn, mouse-wheel zooms, middle-drag
pans, `Home` resets the camera.

## Cleanup

```bash
taskkill //F //IM Godot_v4.7.2-stable_win64.exe //IM Godot_v4.7.2-stable_win64_console.exe 2>&1
```

Kill stale instances before relaunching — several can stack up across attempts
and confuse process/window lookups.

## Gotchas

- Piping the game's stdout through `head` sends SIGPIPE and **kills the game**
  when the pipe closes. Use `> file` or `| cat`, never `| head`.
- `NVAPI: ... NVAPI_EXECUTABLE_ALREADY_IN_USE(code -167)` on startup is harmless.
- Line endings are CRLF; `git` warns about it. Leave it.
