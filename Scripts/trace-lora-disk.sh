#!/bin/bash
# trace-lora-disk.sh — wrap afm-probe with filesystem + block-level tracing
# to measure the AFM LoRA APFS metadata leak documented at
# https://developer.apple.com/forums/thread/823001
#
# The primary ground-truth signal is `df -b` free-space delta on
# /System/Volumes/Data. No individual file write accounts for the loss,
# so don't expect `find -newer` to show anything.
#
# Usage:
#   sudo Scripts/trace-lora-disk.sh [options]
#
# Options:
#   --calls N            inference calls per run (default 3)
#   --adapter-name NAME  registered adapter name (default junco_coding)
#   --adapter-path PATH  .fmadapter file path (overrides --adapter-name)
#   --no-adapter         skip adapter load (single-run mode only)
#   --compare            run twice, with then without adapter, and diff
#   --sysdiagnose        capture a sysdiagnose archive at the end
#   --delay-before N     probe pre-trace sleep seconds (default 3)
#
# Requires sudo for fs_usage/log-stream to observe other processes
# (notably TGOnDeviceInferenceProviderService).

set -euo pipefail

# -------- arg parsing ----------------------------------------------------
CALLS=3
ADAPTER_NAME="junco_coding"
ADAPTER_PATH=""
NO_ADAPTER=0
COMPARE=0
SYSDIAGNOSE=0
DELAY=3

while [[ $# -gt 0 ]]; do
  case "$1" in
    --calls) CALLS="$2"; shift 2;;
    --adapter-name) ADAPTER_NAME="$2"; shift 2;;
    --adapter-path) ADAPTER_PATH="$2"; shift 2;;
    --no-adapter) NO_ADAPTER=1; shift;;
    --compare) COMPARE=1; shift;;
    --sysdiagnose) SYSDIAGNOSE=1; shift;;
    --delay-before) DELAY="$2"; shift 2;;
    -h|--help) grep -E "^#( |$)" "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  echo "error: must run under sudo (fs_usage / log stream require root)" >&2
  exit 1
fi

# -------- paths ----------------------------------------------------------
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="/tmp/lora-disk-trace/$STAMP"
PROBE_BIN="$REPO_ROOT/.build/release/afm-probe"

mkdir -p "$OUT_DIR"
echo "out: $OUT_DIR"

# -------- build ----------------------------------------------------------
echo "--- building afm-probe ---"
# run swift as the invoking user so ~/Library/Caches permissions stay sane
SUDO_USER_NAME="${SUDO_USER:-$(whoami)}"
sudo -u "$SUDO_USER_NAME" sh -c "cd '$REPO_ROOT' && swift build -c release --product afm-probe" \
  > "$OUT_DIR/build.log" 2>&1
if [[ ! -x "$PROBE_BIN" ]]; then
  echo "error: probe binary missing at $PROBE_BIN (see $OUT_DIR/build.log)" >&2
  exit 1
fi

# -------- one full run: pre-measure, trace, probe, post-measure ---------
# args: <label> <probe-flags...>
run_once() {
  local label="$1"; shift
  local run_dir="$OUT_DIR/$label"
  mkdir -p "$run_dir/pre" "$run_dir/post"
  echo "=== run: $label ==="

  # pre-measurements
  df -b /System/Volumes/Data > "$run_dir/pre/df.blocks" 2>&1 || true
  df -h /System/Volumes/Data > "$run_dir/pre/df.human" 2>&1 || true
  diskutil apfs list > "$run_dir/pre/apfs.list" 2>&1 || true
  tmutil listlocalsnapshots / > "$run_dir/pre/snapshots" 2>&1 || true
  pgrep -lf TGOnDeviceInferenceProviderService > "$run_dir/pre/tg_pids" 2>&1 || true

  # start tracers
  fs_usage -w -e > "$run_dir/fs_usage.log" 2>&1 &
  FS_PID=$!
  log stream --style syslog \
    --predicate 'process == "TGOnDeviceInferenceProviderService" OR subsystem CONTAINS[c] "foundationmodels" OR subsystem CONTAINS[c] "modelcatalog"' \
    > "$run_dir/log_stream.log" 2>&1 &
  LOG_PID=$!
  iostat -w 1 -d disk0 > "$run_dir/iostat.log" 2>&1 &
  IOS_PID=$!

  sleep 1

  # probe — run as the invoking (non-root) user: FoundationModels rejects
  # root with "Running as root is not supported."
  echo "--- running probe (as $SUDO_USER_NAME) ---"
  if ! sudo -u "$SUDO_USER_NAME" "$PROBE_BIN" "$@" > "$run_dir/probe.log" 2>&1; then
    echo "warning: probe exited non-zero (see $run_dir/probe.log)" >&2
  fi

  # stop tracers
  kill "$FS_PID" "$LOG_PID" "$IOS_PID" 2>/dev/null || true
  wait "$FS_PID" "$LOG_PID" "$IOS_PID" 2>/dev/null || true

  # post-measurements
  df -b /System/Volumes/Data > "$run_dir/post/df.blocks" 2>&1 || true
  df -h /System/Volumes/Data > "$run_dir/post/df.human" 2>&1 || true
  diskutil apfs list > "$run_dir/post/apfs.list" 2>&1 || true
  tmutil listlocalsnapshots / > "$run_dir/post/snapshots" 2>&1 || true

  summarize "$label" "$run_dir"
}

# summarize one run_dir into $run_dir/summary.txt
summarize() {
  local label="$1"
  local run_dir="$2"

  python3 - "$label" "$run_dir" "$CALLS" <<'PY' > "$run_dir/summary.txt"
import os, re, sys, collections, pathlib
label, run_dir, calls = sys.argv[1], sys.argv[2], int(sys.argv[3])

def read(p):
    try: return pathlib.Path(p).read_text(errors="replace")
    except FileNotFoundError: return ""

def df_avail_blocks(text):
    # df -b prints header then one line: Filesystem 512-blocks Used Available ...
    for line in text.splitlines():
        parts = line.split()
        if len(parts) >= 4 and parts[1].isdigit():
            return int(parts[3])  # available 512B blocks
    return None

def apfs_capacity_in_use(text):
    # diskutil spells it "Capacity In Use By Volumes" (capital B).
    # Prefer the container that has disk3sX volumes (the data container);
    # fall back to the first match.
    blocks = text.split("APFS Container Reference:")
    target = None
    for blk in blocks:
        if re.search(r"disk3s\d+", blk):
            target = blk
            break
    if target is None:
        target = text
    m = re.search(r"Capacity In Use By Volumes:\s+(\d+)", target, re.IGNORECASE)
    return int(m.group(1)) if m else None

pre_df  = df_avail_blocks(read(f"{run_dir}/pre/df.blocks"))
post_df = df_avail_blocks(read(f"{run_dir}/post/df.blocks"))
pre_ap  = apfs_capacity_in_use(read(f"{run_dir}/pre/apfs.list"))
post_ap = apfs_capacity_in_use(read(f"{run_dir}/post/apfs.list"))

pre_snap  = read(f"{run_dir}/pre/snapshots").strip().splitlines()
post_snap = read(f"{run_dir}/post/snapshots").strip().splitlines()
new_snaps = sorted(set(post_snap) - set(pre_snap))

lines = []
lines.append(f"=== Run: {label} ===")
lines.append(f"calls: {calls}")

if pre_df is not None and post_df is not None:
    delta_blocks = post_df - pre_df  # negative = space consumed
    delta_mb = delta_blocks * 512 / (1024*1024)
    lines.append(f"Volume /System/Volumes/Data free delta: {delta_blocks:+d} x 512B  ({delta_mb:+.1f} MB)")
    if calls > 0:
        lines.append(f"  per call: {delta_mb/calls:+.1f} MB")
else:
    lines.append("Volume free delta: (could not parse df -b)")

if pre_ap is not None and post_ap is not None:
    d = post_ap - pre_ap
    lines.append(f"APFS container 'Capacity In Use' delta: {d:+d} bytes ({d/(1024*1024):+.1f} MB)")
else:
    lines.append("APFS container delta: (could not parse diskutil apfs list)")

lines.append(f"New local snapshots during window: {len(new_snaps)}")
for s in new_snaps:
    lines.append(f"  {s}")

# fs_usage: count RdMeta / WrMeta per process
# Line tail is always "<elapsed>  W  <proc>.<tid>" (the "W" is a wait-flag
# indicator fs_usage always emits for these events). Split from the right.
meta_by_proc = collections.Counter()
meta_events = {"RdMeta": collections.Counter(), "WrMeta": collections.Counter()}
write_by_proc = collections.Counter()
file_writes = collections.Counter()

def parse_tail(line):
    """Return (head, proc) where proc is the process name without thread id."""
    rs = line.rstrip().rsplit(None, 3)
    if len(rs) < 4:
        return line.rstrip(), "?"
    head, _elapsed, _flag, proc_tid = rs
    proc = proc_tid.rsplit(".", 1)[0] if "." in proc_tid else proc_tid
    return head, proc

def extract_wrdata_path(head):
    """WrData head looks like:
       '<ts>  WrData[flags]  D=0x...  B=0x...  /dev/diskNsM  /actual/path possibly with spaces'
       Paths can contain spaces; we split on 2+ spaces as column delimiter and
       keep the last absolute path that isn't under /dev/."""
    cols = re.split(r" {2,}", head)
    paths = [c for c in cols if c.startswith("/")]
    non_dev = [p for p in paths if not p.startswith("/dev/")]
    return (non_dev or paths or [None])[-1]

with open(f"{run_dir}/fs_usage.log", "r", errors="replace") as f:
    for line in f:
        if "RdMeta" in line or "WrMeta" in line:
            _, proc = parse_tail(line)
            kind = "RdMeta" if "RdMeta" in line else "WrMeta"
            meta_events[kind][proc] += 1
            meta_by_proc[proc] += 1
            continue
        # file-level writes: capture WrData specifically (pwrite has no visible path)
        if "WrData" in line:
            head, proc = parse_tail(line)
            path = extract_wrdata_path(head)
            if path:
                file_writes[path] += 1
                write_by_proc[proc] += 1

lines.append("")
lines.append("fs_usage metadata events on /dev/disk3 (top 15 processes):")
for proc, cnt in meta_by_proc.most_common(15):
    rd = meta_events["RdMeta"][proc]
    wr = meta_events["WrMeta"][proc]
    lines.append(f"  {proc:40s}  RdMeta={rd:6d}  WrMeta={wr:6d}")

lines.append("")
lines.append("fs_usage WrData events by process (top 10):")
for proc, cnt in write_by_proc.most_common(10):
    lines.append(f"  {proc:40s}  WrData={cnt:6d}")

lines.append("")
lines.append("Top 20 WrData paths (file-level writes; leak itself is metadata-only):")
for path, cnt in file_writes.most_common(20):
    lines.append(f"  {cnt:6d}  {path}")

# tail of log_stream for subsystem context
ls = read(f"{run_dir}/log_stream.log").splitlines()
lines.append("")
lines.append(f"log_stream.log: {len(ls)} lines; last 20:")
for l in ls[-20:]:
    lines.append(f"  {l}")

print("\n".join(lines))
PY
  cat "$run_dir/summary.txt"
}

# -------- assemble probe flags ------------------------------------------
build_probe_flags() {
  # $1 = "adapter" or "no-adapter"
  local mode="$1"
  local flags=(--calls "$CALLS" --delay-before "$DELAY")
  if [[ "$mode" == "no-adapter" ]]; then
    flags+=(--no-adapter)
  else
    if [[ -n "$ADAPTER_PATH" ]]; then
      flags+=(--adapter-path "$ADAPTER_PATH")
    fi
    flags+=(--adapter-name "$ADAPTER_NAME")
  fi
  printf '%s\n' "${flags[@]}"
}

# -------- execute runs --------------------------------------------------
read_flags() {
  # $1 = mode; populates global array FLAGS_OUT (bash 3.2 compatible; no mapfile).
  FLAGS_OUT=()
  while IFS= read -r __line; do
    FLAGS_OUT+=("$__line")
  done < <(build_probe_flags "$1")
}

if [[ $COMPARE -eq 1 ]]; then
  read_flags adapter
  run_once "with-adapter" "${FLAGS_OUT[@]}"
  echo
  echo "--- settling 5s before control run ---"
  sleep 5
  read_flags no-adapter
  run_once "without-adapter" "${FLAGS_OUT[@]}"

  # combined diff
  python3 - "$OUT_DIR" "$CALLS" <<'PY' > "$OUT_DIR/compare.txt"
import sys, re, pathlib
out, calls = sys.argv[1], int(sys.argv[2])
def df_avail(p):
    try: t = pathlib.Path(p).read_text()
    except FileNotFoundError: return None
    for ln in t.splitlines():
        pts = ln.split()
        if len(pts) >= 4 and pts[1].isdigit():
            return int(pts[3])
    return None
def delta_mb(pre, post):
    if pre is None or post is None: return None
    return (post - pre) * 512 / (1024*1024)

a_pre  = df_avail(f"{out}/with-adapter/pre/df.blocks")
a_post = df_avail(f"{out}/with-adapter/post/df.blocks")
n_pre  = df_avail(f"{out}/without-adapter/pre/df.blocks")
n_post = df_avail(f"{out}/without-adapter/post/df.blocks")
a = delta_mb(a_pre, a_post)
n = delta_mb(n_pre, n_post)
print("=== Adapter-attributable leak ===")
if a is None or n is None:
    print("  (could not parse df -b outputs)")
else:
    print(f"  With adapter:    {a:+.1f} MB free-space delta across {calls} calls ({a/calls:+.1f} MB/call)")
    print(f"  Without adapter: {n:+.1f} MB free-space delta across {calls} calls ({n/calls:+.1f} MB/call)")
    attributable = (a - n) / calls
    print(f"  Adapter-attributable: ~{attributable:+.1f} MB per call")
PY
  echo
  cat "$OUT_DIR/compare.txt"
else
  if [[ $NO_ADAPTER -eq 1 ]]; then
    read_flags no-adapter
    run_once "no-adapter" "${FLAGS_OUT[@]}"
  else
    read_flags adapter
    run_once "with-adapter" "${FLAGS_OUT[@]}"
  fi
fi

# -------- optional sysdiagnose ------------------------------------------
if [[ $SYSDIAGNOSE -eq 1 ]]; then
  echo "--- capturing sysdiagnose (this takes several minutes) ---"
  sysdiagnose -f "$OUT_DIR" -u -b 2>&1 | tee "$OUT_DIR/sysdiagnose.log"
fi

echo
echo "=== all artifacts in: $OUT_DIR ==="
ls -la "$OUT_DIR"
