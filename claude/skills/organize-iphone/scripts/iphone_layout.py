"""Read and rewrite the iPhone home screen layout over USB (SpringBoard services).

  status                    is an iPhone connected?
  snapshot [-o FILE]        current layout as simplified JSON, with ids to plan with
  apply PLAN [--dry-run]    back up, write the plan, verify
  restore [BACKUP]          write a backup back (default: the newest one)

Plan format (every app, widget and web clip in the snapshot must appear exactly once):
  {"dock": ["app:com.google.ios.youtube", ...],
   "pages": [["app:...", {"folder": "Finance", "apps": ["app:...", ...]}, "widget:...", "clip:..."], ...],
   "overflow_folder": "Other"}

iOS quirks this works around:
  - getIconState omits hidden pages; on write, iOS appends any app missing from the new
    state onto visible pages. Those get swept into `overflow_folder` with a second write.
  - iOS re-normalizes a widget's position within a page, so order diffs are reported, not fatal.
"""
import argparse
import asyncio
import copy
import datetime
import json
import plistlib
import sys
from collections import Counter
from pathlib import Path

from pymobiledevice3.exceptions import NoDeviceConnectedError
from pymobiledevice3.lockdown import create_using_usbmux
from pymobiledevice3.services.springboard import SpringBoardServicesService

BACKUPS = Path.home() / ".local/share/organize-iphone/backups"  # personal; the skill dir is a public repo
PAGE_CELLS = 24  # 6 rows x 4 columns
DOCK_SLOTS = 4
FOLDER_PAGE = 9
WIDGET_CELLS = {"small": 4, "medium": 8, "large": 16}


class PlanError(Exception):
    pass


def kind(it):
    if it.get("elementType") == "widget":
        return "widget"
    if it.get("listType") == "folder" or ("iconLists" in it and "bundleIdentifier" not in it):
        return "folder"
    if "webClipURL" in it:
        return "clip"
    if "bundleIdentifier" in it:
        return "app"
    return "item"


def ident(it):
    k = kind(it)
    if k == "app":
        return f"app:{it['bundleIdentifier']}"
    return f"{k}:{it.get('displayIdentifier') or it.get('displayName')}"


def cells(it):
    return WIDGET_CELLS.get(it.get("gridSize"), 4) if kind(it) == "widget" else 1


def walk_leaves(state):
    for page in state:
        for it in page:
            if kind(it) == "folder":
                for fpage in it["iconLists"]:
                    yield from fpage
            else:
                yield it


def leaves(state):
    return Counter(ident(it) for it in walk_leaves(state))


def label(it):
    if kind(it) == "widget":
        return f"{it.get('widgetIdentifier')} widget [{it.get('gridSize')}]"
    return it.get("displayName") or ident(it)


def simplify(it):
    if kind(it) == "folder":
        return {"folder": it.get("displayName"), "apps": [simplify(s) for p in it["iconLists"] for s in p]}
    d = {"id": ident(it), "name": label(it)}
    if kind(it) == "widget":
        d["app"] = it.get("containerBundleIdentifier")
        d["size"] = it.get("gridSize")
    return d


def render(state):
    out = []
    for n, page in enumerate(state):
        used = sum(cells(it) for it in page)
        head = f"DOCK ({len(page)}/{DOCK_SLOTS})" if n == 0 else f"PAGE {n} ({used}/{PAGE_CELLS} cells)"
        names = [f"[{it.get('displayName')}: {sum(len(p) for p in it['iconLists'])} apps]" if kind(it) == "folder" else label(it)
                 for it in page]
        out.append(f"{head}: " + " | ".join(names))
    return "\n".join(out)


async def lockdown():
    try:
        return await create_using_usbmux()
    except NoDeviceConnectedError:
        sys.exit("NO_DEVICE: no iPhone found over USB. Plug it in, unlock it, and tap Trust if asked.")


async def connect():
    return SpringBoardServicesService(await lockdown())


async def read_state():
    return await (await connect()).get_icon_state()


def save_backup(state, tag):
    BACKUPS.mkdir(parents=True, exist_ok=True)
    path = BACKUPS / f"{datetime.datetime.now():%Y-%m-%d_%H%M%S}-{tag}.plist"
    with open(path, "wb") as f:
        plistlib.dump(state, f)
    return path


def build(plan, raw_by_id):
    used = Counter()

    def leaf(i):
        if i not in raw_by_id:
            raise PlanError(f"unknown id {i!r}")
        used[i] += 1
        return copy.deepcopy(raw_by_id[i])

    def entry(e):
        if isinstance(e, str):
            return leaf(e)
        if isinstance(e, dict) and "folder" in e:
            members = [leaf(a) for a in e["apps"]]
            if not members:
                raise PlanError(f"folder {e['folder']!r} is empty")
            if any(kind(m) == "widget" for m in members):
                raise PlanError(f"folder {e['folder']!r} contains a widget")
            return {"displayName": e["folder"], "listType": "folder",
                    "iconLists": [members[i:i + FOLDER_PAGE] for i in range(0, len(members), FOLDER_PAGE)]}
        raise PlanError(f"bad entry {e!r}")

    dock = [entry(e) for e in plan["dock"]]
    pages = [[entry(e) for e in p] for p in plan["pages"]]
    if len(dock) > DOCK_SLOTS:
        raise PlanError(f"dock has {len(dock)} items, max {DOCK_SLOTS}")
    if any(kind(it) == "widget" for it in dock):
        raise PlanError("widgets can't go in the dock")
    for n, page in enumerate(pages, 1):
        if not page:
            raise PlanError(f"page {n} is empty")
        if sum(cells(it) for it in page) > PAGE_CELLS:
            raise PlanError(f"page {n} uses {sum(cells(it) for it in page)} cells, max {PAGE_CELLS}")
    missing = [raw_by_id[i] for i in raw_by_id if i not in used]
    if missing:
        raise PlanError("plan leaves out: " + ", ".join(f"{label(m)} ({ident(m)})" for m in missing))
    dupes = [i for i, c in used.items() if c > 1]
    if dupes:
        raise PlanError(f"listed more than once: {dupes}")
    return [dock] + pages


def sweep_extras(intended, after, folder_name):
    """Put apps iOS surfaced from hidden pages into `folder_name` on the last page."""
    extra = set(leaves(after)) - set(leaves(intended))
    loose = [copy.deepcopy(it) for page in after for it in page if kind(it) != "folder" and ident(it) in extra]
    new = copy.deepcopy(intended)
    folder = next((it for page in new[1:] for it in page if kind(it) == "folder" and it.get("displayName") == folder_name), None)
    if folder:
        members = [m for p in folder["iconLists"] for m in p] + loose
        folder["iconLists"] = [members[i:i + FOLDER_PAGE] for i in range(0, len(members), FOLDER_PAGE)]
    else:
        folder = {"displayName": folder_name, "listType": "folder",
                  "iconLists": [loose[i:i + FOLDER_PAGE] for i in range(0, len(loose), FOLDER_PAGE)]}
        if len(new) > 1 and sum(cells(it) for it in new[-1]) < PAGE_CELLS:
            new[-1].append(folder)
        else:
            new.append([folder])
    return new, [label(it) for it in loose]


async def write_and_verify(new, overflow_folder=None):
    await (await connect()).set_icon_state(new)
    await asyncio.sleep(1)
    after = await read_state()
    extra = set(leaves(after)) - set(leaves(new))
    if extra and overflow_folder:
        new, swept = sweep_extras(new, after, overflow_folder)
        print(f"iOS surfaced {len(swept)} apps from hidden pages; moved them into '{overflow_folder}': {', '.join(swept)}")
        await (await connect()).set_icon_state(new)
        await asyncio.sleep(1)
        after = await read_state()
    lost = set(leaves(new)) - set(leaves(after))
    extra = set(leaves(after)) - set(leaves(new))
    if lost:
        print(f"WARNING: missing after write: {sorted(lost)}")
    if extra:
        print(f"WARNING: unexpected items after write: {sorted(extra)}")
    seq = lambda st: [[ident(it) if kind(it) != "folder" else
                       ("folder:" + it.get("displayName", ""), [ident(m) for fp in it["iconLists"] for m in fp])
                       for it in p] for p in st]
    for n, (a, b) in enumerate(zip(seq(new), seq(after))):
        if a != b:
            where = "dock" if n == 0 else f"page {n}"
            print(f"note: iOS adjusted the order on {where} (usually widget placement)")
    if len(new) != len(after):
        print(f"note: intended {len(new) - 1} pages, phone now has {len(after) - 1}")
    print("VERIFIED" if not lost and not extra else "CHECK THE PHONE")
    print(render(after))


async def cmd_status(args):
    ld = await lockdown()
    print(f"{ld.display_name} — iOS {ld.product_version} (build {ld.product_build_version}) — {ld.product_type}")


async def cmd_snapshot(args):
    state = await read_state()
    snap = {"dock": [simplify(it) for it in state[0]],
            "pages": [[simplify(it) for it in page] for page in state[1:]],
            "page_cells_used": [sum(cells(it) for it in page) for page in state[1:]]}
    text = json.dumps(snap, ensure_ascii=False, indent=1)
    if args.output:
        Path(args.output).write_text(text)
        print(render(state))
        print(f"\n{sum(leaves(state).values())} items; snapshot written to {args.output}")
    else:
        print(text)


async def cmd_apply(args):
    plan = json.loads(Path(args.plan).read_text())
    state = await read_state()
    raw_by_id = {ident(it): it for it in walk_leaves(state)}
    try:
        new = build(plan, raw_by_id)
    except PlanError as e:
        sys.exit(f"PLAN_ERROR: {e}")
    print(render(new))
    if args.dry_run:
        print("\nDRY RUN: plan is valid, nothing written")
        return
    print(f"\nbackup: {save_backup(state, 'before-apply')}")
    await write_and_verify(new, plan.get("overflow_folder", "Other"))


async def cmd_restore(args):
    path = Path(args.backup) if args.backup else max(BACKUPS.glob("*.plist"))
    target = plistlib.load(open(path, "rb"))
    current = await read_state()
    present = set(leaves(current))
    # Drop apps uninstalled since the backup; empty folders go with them.
    pruned = []
    for page in target:
        keep = []
        for it in page:
            if kind(it) == "folder":
                members = [m for p in it["iconLists"] for m in p if ident(m) in present]
                if members:
                    keep.append({**it, "iconLists": [members[i:i + FOLDER_PAGE] for i in range(0, len(members), FOLDER_PAGE)]})
            elif ident(it) in present:
                keep.append(it)
        pruned.append(keep)
    pruned = [pruned[0]] + [p for p in pruned[1:] if p]
    # Anything on the phone that the backup doesn't have goes loose onto trailing pages.
    have = set(leaves(pruned))
    extras = [it for it in walk_leaves(current) if ident(it) not in have]
    while extras:
        pruned.append(extras[:PAGE_CELLS])
        extras = extras[PAGE_CELLS:]
    print(f"restoring {path.name}")
    print(render(pruned))
    if args.dry_run:
        print("\nDRY RUN: nothing written")
        return
    print(f"\nbackup of current layout: {save_backup(current, 'before-restore')}")
    await write_and_verify(pruned)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("status")
    s = sub.add_parser("snapshot")
    s.add_argument("-o", "--output")
    a = sub.add_parser("apply")
    a.add_argument("plan")
    a.add_argument("--dry-run", action="store_true")
    r = sub.add_parser("restore")
    r.add_argument("backup", nargs="?")
    r.add_argument("--dry-run", action="store_true")
    args = p.parse_args()
    asyncio.run({"status": cmd_status, "snapshot": cmd_snapshot, "apply": cmd_apply, "restore": cmd_restore}[args.cmd](args))


if __name__ == "__main__":
    main()
