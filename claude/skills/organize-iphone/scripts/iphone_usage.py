"""Per-app iPhone usage from the App.InFocus events the iPhone syncs to this Mac (Biome).

  iphone_usage.py [--days 28] [--build 24A446] [--json]

Screen Time's own store (com.apple.ScreenTimeAgent) is locked even with Full Disk Access, but
Biome syncs the iPhone's raw "app came into / left focus" events to
~/Library/Biome/streams/restricted/App.InFocus/remote/<device id>/. Reading them needs Full
Disk Access for the terminal. Sync lags a few days, which is fine for layout decisions.

Prints, per app: launches (times it came into focus), launches straight from the home screen
(icon or folder taps, which is what layout affects), and foreground hours.
"""
import argparse
import datetime
import json
import sqlite3
import struct
import sys
import zlib
from collections import defaultdict
from pathlib import Path

BIOME = Path.home() / "Library/Biome"
STREAM = BIOME / "streams/restricted/App.InFocus/remote"
MAC_EPOCH = datetime.datetime(2001, 1, 1, tzinfo=datetime.timezone.utc)
IOS_PLATFORM = 2
# Not apps the user opens; SpringBoard surfaces and system UI that also report focus.
IGNORE_PREFIXES = ("com.apple.springboard", "com.apple.SpringBoard", "com.apple.InCallService",
                   "com.apple.PassbookUIService", "com.apple.CarPlay", "com.apple.siri",
                   "com.apple.ScreenTimeUnlock", "com.apple.AccountAuthenticationDialog")


def varint(buf, i):
    shift = result = 0
    while True:
        b = buf[i]
        i += 1
        result |= (b & 0x7F) << shift
        if not b & 0x80:
            return result, i
        shift += 7


def protobuf_fields(buf):
    """Flat {field_number: value} for one record (repeated fields keep the last value)."""
    out, i = {}, 0
    while i < len(buf):
        key, i = varint(buf, i)
        field, wire = key >> 3, key & 7
        if wire == 0:
            out[field], i = varint(buf, i)
        elif wire == 1:
            out[field] = struct.unpack_from("<d", buf, i)[0]
            i += 8
        elif wire == 2:
            n, i = varint(buf, i)
            out[field] = buf[i:i + n]
            i += n
        elif wire == 5:
            i += 4
        else:
            raise ValueError(f"wire type {wire}")
    return out


def segb_records(path):
    """Records of a SEGB v2 file: 32-byte header, 4-byte-aligned entries (CRC32 of the data,
    4 unknown bytes, protobuf data), and a trailer of 16-byte (end offset, state, timestamp)
    items written backwards from the end of the file. A few trailer offsets are inconsistent,
    so every record is checked against its CRC."""
    data = path.read_bytes()
    if data[:4] != b"SEGB":
        return
    count = struct.unpack_from("<I", data, 4)[0]
    start = 0
    for n in range(count):
        end, state = struct.unpack_from("<II", data, len(data) - 16 * (n + 1))
        record = data[0x20 + start + 8:0x20 + end]
        # state 1 = written; 3 = deleted
        if state == 1 and zlib.crc32(record) == struct.unpack_from("<I", data, 0x20 + start)[0]:
            yield record
        start = (end + 3) & ~3


def iphone_device_dir(build=None):
    db = sqlite3.connect(f"file:{BIOME / 'sync/sync.db'}?mode=ro", uri=True)
    rows = db.execute("select device_identifier, model, last_sync_date from DevicePeer "
                      "where me = 0 and platform = ? order by last_sync_date desc", (IOS_PLATFORM,)).fetchall()
    if build:
        rows = [r for r in rows if r[1] == build] or rows
    for device, model, synced in rows:
        if (STREAM / device).is_dir():
            return STREAM / device, model, synced
    sys.exit("NO_DATA: no synced iPhone usage found in Biome. Is Screen Time 'Share Across Devices' on?")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--days", type=int, default=28)
    p.add_argument("--build", help="iPhone OS build (from `iphone_layout.py status`) to pick the right device")
    p.add_argument("--json", action="store_true")
    args = p.parse_args()

    try:
        device_dir, build, synced = iphone_device_dir(args.build)
        files = [f for f in device_dir.iterdir() if f.is_file()]
    except (PermissionError, sqlite3.OperationalError):
        sys.exit("NO_ACCESS: the terminal needs Full Disk Access to read ~/Library/Biome.")

    since = (datetime.datetime.now(datetime.timezone.utc) - MAC_EPOCH).total_seconds() - args.days * 86400
    # Field meanings, from inspection: 1 = transition reason (on entering), 2 = 1 for apps
    # (3 = SpringBoard elements like open folders), 3 = 1 entering / 0 leaving focus,
    # 4 = timestamp (seconds since 2001), 6 = bundle id.
    events = []
    for f in files:
        for rec in segb_records(f):
            try:
                fields = protobuf_fields(rec)
            except (ValueError, IndexError, struct.error):
                continue
            if fields.get(2) == 1 and 6 in fields and 4 in fields and fields[4] >= since:
                reason = fields.get(1, b"").decode(errors="replace")
                events.append((fields[4], fields[6].decode(errors="replace"), fields.get(3, 0), reason))
    events.sort()

    stats = defaultdict(lambda: {"launches": 0, "from_home_screen": 0, "seconds": 0.0})
    open_since = {}
    for ts, bundle, entering, reason in events:
        if bundle.startswith(IGNORE_PREFIXES):
            continue
        if entering:
            stats[bundle]["launches"] += 1
            if "transitionReason.homescreen" in reason or "home-screen" in reason:
                stats[bundle]["from_home_screen"] += 1
            open_since[bundle] = ts
        elif bundle in open_since:
            stats[bundle]["seconds"] += min(ts - open_since.pop(bundle), 4 * 3600)

    first = events[0][0] if events else since
    last = events[-1][0] if events else since
    to_date = lambda s: (MAC_EPOCH + datetime.timedelta(seconds=s)).astimezone().strftime("%Y-%m-%d %H:%M")
    rows = sorted(stats.items(), key=lambda kv: (-kv[1]["launches"], -kv[1]["seconds"]))
    if args.json:
        print(json.dumps({"device_build": build, "from": to_date(first), "to": to_date(last),
                          "apps": {b: {**s, "hours": round(s["seconds"] / 3600, 2)} for b, s in rows}}, indent=1))
        return
    print(f"iPhone (build {build}) usage {to_date(first)} → {to_date(last)} ({(last - first) / 86400:.1f} days)")
    print(f"{'launches':>8} {'from home':>9} {'hours':>7}  bundle id")
    for bundle, s in rows:
        print(f"{s['launches']:>8} {s['from_home_screen']:>9} {s['seconds'] / 3600:>7.1f}  {bundle}")


if __name__ == "__main__":
    main()
