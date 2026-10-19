"""Build a layout plan from app categories and tap counts (the user's left-thumb layout).

  make_plan.py SNAPSHOT USAGE CATEGORIES [-o PLAN]

SNAPSHOT is `iphone_layout.py snapshot -o` output, USAGE is `iphone_usage.py --json` output.
CATEGORIES files every app into a folder, frequent ones included, so an app that drops out
of the top spots falls back into its folder:
  {"folders": {"Messaging": ["app:jp.naver.line", ...], ...},
   "dock": [...], "loose": [...]}      # optional: pin these instead of ranking by taps

Ranking is by taps (launches from the home screen), then all launches, then hours.
  dock      the 4 most-tapped apps
  page 1    the next 10 in the bottom-left triangle (rows 3-6 hold 1, 2, 3, 4 of them),
            the most-tapped nearest the corner. iOS fills left to right, top to bottom and
            won't keep gaps over USB, so 14 folders fill the other cells to push the apps
            down; the most-used folders sit nearest the triangle.
  page 2    any folders beyond 14, and widgets
"""
import argparse
import json
import math
import sys
from pathlib import Path

ROWS, COLS, DOCK_SLOTS, CORNER = 6, 4, 4, 4
# (row, col) with row 0 at the top. Triangle cells: within CORNER - 1 steps of the corner.
CELLS = [(r, c) for r in range(ROWS) for c in range(COLS)]
near_corner = lambda rc: (math.hypot(ROWS - 1 - rc[0], rc[1]), ROWS - 1 - rc[0])
TRIANGLE = sorted((rc for rc in CELLS if (ROWS - 1 - rc[0]) + rc[1] < CORNER), key=near_corner)
FOLDER_CELLS = sorted((rc for rc in CELLS if rc not in TRIANGLE), key=near_corner)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("snapshot")
    p.add_argument("usage")
    p.add_argument("categories")
    p.add_argument("-o", "--output", default="plan.json")
    a = p.parse_args()
    snap = json.loads(Path(a.snapshot).read_text())
    usage = json.loads(Path(a.usage).read_text())["apps"]
    cats = json.loads(Path(a.categories).read_text())

    names = {}

    def collect(it):
        if "folder" in it:
            for m in it["apps"]:
                collect(m)
        else:
            names[it["id"]] = it["name"]

    for it in snap["dock"] + [i for page in snap["pages"] for i in page]:
        collect(it)

    def score(i):
        s = usage.get("com.apple.webapp" if i.startswith("clip:") else i.split(":", 1)[1], {})
        return (s.get("from_home_screen", 0), s.get("launches", 0), s.get("seconds", 0))

    taps = lambda i: score(i)[0]
    widgets = [i for i in names if i.startswith("widget:")]
    filed = [i for apps in cats["folders"].values() for i in apps]
    errors = []
    if unknown := [i for i in filed if i not in names]:
        errors.append(f"not on the phone (uninstalled?): {unknown}")
    if dupes := sorted({i for i in filed if filed.count(i) > 1}):
        errors.append(f"in more than one folder: {dupes}")
    if missing := [f"{names[i]} ({i})" for i in names if i not in filed and i not in widgets]:
        errors.append(f"not in any folder: {missing}")
    if errors:
        sys.exit("CATEGORY_ERROR: " + "\n  ".join(errors))

    ranked = sorted((i for i in names if i not in widgets), key=score, reverse=True)
    dock = cats.get("dock") or ranked[:DOCK_SLOTS]
    loose = cats.get("loose") or [i for i in ranked if i not in dock][:len(TRIANGLE)]
    loose = sorted(loose, key=score, reverse=True)
    if len(dock) > DOCK_SLOTS or len(loose) != len(TRIANGLE):
        sys.exit(f"CATEGORY_ERROR: need at most {DOCK_SLOTS} dock apps and exactly {len(TRIANGLE)} loose apps")

    folders = {name: sorted((i for i in apps if i not in dock and i not in loose), key=score, reverse=True)
               for name, apps in cats["folders"].items()}
    folders = {k: v for k, v in folders.items() if v}
    order = sorted(folders, key=lambda k: (sum(taps(i) for i in folders[k]), sum(score(i)[1] for i in folders[k])),
                   reverse=True)
    if len(order) < len(FOLDER_CELLS):
        sys.exit(f"CATEGORY_ERROR: page 1 needs {len(FOLDER_CELLS)} non-empty folders to push the apps into the "
                 f"corner, have {len(order)}. Split a big category.")

    grid = dict(zip(TRIANGLE, loose)) | dict(zip(FOLDER_CELLS, order))
    page1 = [{"folder": grid[rc], "apps": folders[grid[rc]]} if grid[rc] in folders else grid[rc] for rc in CELLS]
    page2 = [{"folder": k, "apps": folders[k]} for k in order[len(FOLDER_CELLS):]] + widgets
    plan = {"dock": dock, "pages": [page1] + ([page2] if page2 else []), "overflow_folder": "Other"}
    Path(a.output).write_text(json.dumps(plan, ensure_ascii=False, indent=1))

    label = lambda x: f"[{x}]" if x in folders else f"{names[x][:13]} {taps(x)}"
    print("DOCK    " + " · ".join(label(i) for i in dock))
    for r in range(ROWS):
        print(("PAGE 1  " if r == 0 else "        ") + "".join(f"{label(grid[(r, c)]):<19}" for c in range(COLS)))
    for name in order:
        where = "" if name in order[:len(FOLDER_CELLS)] else "  (page 2)"
        print(f"  {name} ({sum(taps(i) for i in folders[name])} taps){where}: "
              + ", ".join(f"{names[i]} {taps(i)}" if taps(i) else names[i] for i in folders[name]))
    if widgets:
        print("  page 2 widgets: " + ", ".join(names[i] for i in widgets))
    print(f"\nplan written to {a.output}")


if __name__ == "__main__":
    main()
