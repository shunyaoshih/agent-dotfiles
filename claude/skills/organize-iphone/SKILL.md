---
name: organize-iphone
description: Rearrange the user's iPhone home screen icons by how often they use each app and by category, over USB. Use when the user asks to organize, rearrange, sort, reorganize, clean up or tidy the apps or icons on their iPhone/phone home screen, or to undo or restore a previous phone layout.
---

# Organize iPhone home screen

Writes the home screen layout directly through SpringBoard over USB (pymobiledevice3), using
the iPhone usage events that sync to this Mac. Gather data and plan without hand-holding, but
**show the proposed layout and wait for the user's OK before writing to the phone** (they asked
for this). Undo is always one command away.

```sh
SKILL=~/.claude/skills/organize-iphone
DATA=~/.local/share/organize-iphone      # venv, categories.json, layout backups
PY=$DATA/venv/bin/python
LAYOUT=$SKILL/scripts/iphone_layout.py   # run as $PY $LAYOUT; a "$L" with spaces breaks in zsh
SCRATCH=<the session scratchpad>          # snapshot, usage and plan files go here
```

`$SKILL` is a public dotfiles repo: never write the user's app lists, layouts or usage there.

## 1. Connection

Run `$PY $LAYOUT status` (note the build for step 2). If it prints `NO_DEVICE`, remind the user to plug the iPhone into this Mac
with a cable, unlock it, and tap Trust if asked. Wait for them; don't continue without it.
(The user asked to be reminded about the cable whenever they forget.)

If `$DATA/venv` is missing, rebuild it (`--only-binary` because on an Intel Mac the newest `cryptography` has no x86_64 wheel; also works on Apple Silicon):
`python3 -m venv /tmp/uvboot && /tmp/uvboot/bin/pip install -q uv && /tmp/uvboot/bin/uv venv -p 3.12 $DATA/venv && VIRTUAL_ENV=$DATA/venv /tmp/uvboot/bin/uv pip install --only-binary cryptography pymobiledevice3`.
Don't use Homebrew for this; it builds cmake and uv from source and takes an hour.

## 2. Usage data

Run `$PY $SKILL/scripts/iphone_usage.py --build <BuildVersion from status>` for the last 4
weeks, and again with `--json > $SCRATCH/usage.json` for step 4. It reports: per app, `launches` (times it came to the foreground), `from home` (launched by tapping
its icon on the home screen or in a folder) and foreground `hours`. It reads the App.InFocus
events the iPhone syncs to `~/Library/Biome` (Screen Time's own store is locked even with Full
Disk Access). Sync lags hours to a few days; that's fine. `com.apple.webapp` is home screen
web clips. Ignore bundle ids that aren't in the snapshot (system services, uninstalled apps).

- `NO_ACCESS`: the terminal lacks Full Disk Access. Tell the user: System Settings → Privacy &
  Security → Full Disk Access → turn on **Ghostty** (Claude runs in tmux under Ghostty), then
  restart Ghostty, and the tmux server too if it still fails. Open the pane for them with
  `open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"`.
  Meanwhile, offer the fallback below.
- `NO_DATA`: Screen Time "Share Across Devices" may be off on the iPhone. Use the fallback.
- Fallback: ask for a screen recording of iPhone Settings → Screen Time → See All App &
  Website Activity → Week, scrolled slowly to the bottom with "Show More" expanded, AirDropped
  to `~/Downloads`. Extract frames into a fresh scratchpad directory with
  `swift $SKILL/scripts/video_frames.swift <video> <dir>` and read them (every 2–4 frames is
  enough; fill gaps when rows are skipped). Use the "Most Used" times and "First Used After
  Pickup" counts.

Rank by `from home` first: those are icon taps, exactly what placement speeds up. Then total
launches, then hours. An app opened mostly via notifications or links (high launches, low
from-home) needs a reachable icon less. Notification counts don't matter.

## 3. Snapshot

`$PY $LAYOUT snapshot -o $SCRATCH/snapshot.json` prints the layout and writes JSON with an `id` for
every app (`app:<bundle id>`), widget (`widget:…`) and web clip (`clip:…`), plus folders.

## 4. Plan

The user's layout (they use the phone left-handed and find apps by category):
- **Dock:** the 4 most-tapped apps.
- **Page 1, bottom-left triangle:** the next 10 most-tapped apps loose. Rows 3–6 hold 1, 2, 3
  and 4 of them, the most-tapped nearest the bottom-left corner.
- **Page 1, everything else: 14 category folders**, holding every other app, frequent ones
  included. The most-used folders sit nearest the triangle.
- No page 2 unless there are more than 14 folders or there's a widget. Never use hidden pages:
  iOS puts hidden-page apps back on every write, so folders are the only stable home.

The shape is fixed because iOS fills a page left to right, top to bottom, and over USB it
left-aligns any gaps. The 14 folders are what push the 10 apps into the corner, so page 1 needs
exactly 14 non-empty folders after the loose apps are taken out.

`$DATA/categories.json` holds the categories the user last approved. Reuse it. File new apps
into a folder, drop uninstalled ones (`make_plan.py` names both), and change existing
categories only when the user asks. If it's missing, write one:

```json
{"folders": {"Messaging": ["app:jp.naver.line", "app:com.apple.MobileSMS"], "Finance": ["app:…"]},
 "dock": ["app:…"], "loose": ["app:…"]}
```

- Every app and web clip in the snapshot goes in exactly one folder, **including dock and
  triangle apps**. `make_plan.py` takes them out, and an app that drops out of the top spots
  falls back into its folder. Widgets go on page 2 by themselves.
- `dock` and `loose` are optional pins, used only when the user asks to fix an app in place.
- Short folder names, about 12 characters at most, or iOS truncates them. Keep the user's names
  from `categories.json`.
- If there are fewer than 14 non-empty folders, split the biggest category, as Transport was
  split from Travel. If there are more, the least-used ones go on page 2.
- Apps are never deleted, only arranged. Never suggest deleting apps.

Then:

```sh
$PY $SKILL/scripts/make_plan.py $SCRATCH/snapshot.json $SCRATCH/usage.json $DATA/categories.json -o $SCRATCH/plan.json
$PY $LAYOUT apply $SCRATCH/plan.json --dry-run
```

`make_plan.py` ranks apps by taps (home-screen launches), then all launches, then hours. It
sorts each folder the same way, so the first 9 apps (the folder's first page) are the useful
ones. It prints the grid and the folders. Fix any `CATEGORY_ERROR` or `PLAN_ERROR`.

The plan format, if you need to hand-edit one: `{"dock": [ids], "pages": [[id or {"folder":
name, "apps": [ids]}, …]], "overflow_folder": "Other"}`. Every snapshot item appears exactly
once. A page holds 24 cells and the dock 4 items. A small widget takes 2×2 cells, a medium
4×2 and a large 4×4.

## 5. Proposal and approval

Show the proposed layout and **stop for the user's approval**. Write nothing yet:
- The dock and page 1 as a grid from `make_plan.py`'s output, with each loose app's 4-week tap
  count.
- Each folder with its apps in order.
- One line for each move, with the reason (e.g. "Strava into Training: 48 taps, just below the
  top 10").

Apply only after an explicit yes. If they ask for changes, edit `categories.json` (or pins),
rerun `make_plan.py`, dry-run, and show the changed parts again.

## 6. Apply

`$PY $LAYOUT apply $SCRATCH/plan.json`. It backs up the current layout to `$DATA/backups/` first,
writes, re-reads, and prints `VERIFIED` or `CHECK THE PHONE`. If iOS surfaces apps from hidden
pages, it moves them into the overflow folder automatically and says so; recategorize them
next time.

"iOS adjusted the order" notes are usually widget placement and are harmless, but mention
them so the user can check.

## 7. Report

Confirm it's applied (`VERIFIED`) and mention any warnings or iOS order adjustments.
End with: say "undo" to put the old layout back.

## Undo / restore

`$PY $LAYOUT restore --dry-run`, then `$PY $LAYOUT restore`. With no argument it restores the newest backup,
which after an apply is the pre-apply layout. Each restore backs up first, so a second undo
flips back. `ls $DATA/backups` lists older layouts; pass a path to restore a specific one.

## Safety

- Never call SpringBoard's `set_icon_state` directly or with no argument; it can wipe the
  layout. Always go through `iphone_layout.py`, which validates and backs up.
- Hidden pages and App-Library-only apps can't be seen or created over this connection.
