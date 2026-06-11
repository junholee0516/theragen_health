#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG="${1:?run_config.sh 필요}"
source "$CONFIG"

echo "============================================================"
echo "[05] QC Call Rate PASS list 생성"
echo "============================================================"

mkdir -p "$(dirname "$CALLRATE_PASS_LIST")" "$FINAL_DIR"

REPORT="$(find "$CALLRATE_DIR" -maxdepth 1 -type f -name "*report.txt" | sort | head -1 || true)"

if [ -z "$REPORT" ] || [ ! -f "$REPORT" ]; then
  echo "[ERROR] QC Call Rate report 파일을 찾지 못했습니다."
  echo "[CHECK] CALLRATE_DIR = $CALLRATE_DIR"
  find "$CALLRATE_DIR" -maxdepth 2 -type f | sort || true
  exit 1
fi

python3 - "$REPORT" "$CEL_LIST" "$CALLRATE_PASS_LIST" "${FINAL_DIR}/QC_CallRate_summary.tsv" "$CALLRATE_THRESHOLD" <<'PY'
import sys, csv, os

report, cel_list, pass_out, summary_out, threshold_raw = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], float(sys.argv[5])

def norm_name(x):
    return os.path.basename(str(x).strip().replace("\\", "/"))

def norm_key(x):
    b = norm_name(x)
    if b.lower().endswith(".cel"):
        b = b[:-4]
    return b

with open(cel_list, "r", encoding="utf-8", errors="replace") as f:
    cels = [x.strip() for x in f if x.strip() and x.strip().lower() != "cel_files"]

cel_by_key = dict((norm_key(x), x) for x in cels)

with open(report, "r", encoding="utf-8", errors="replace") as f:
    lines = [x for x in f if x.strip() and not x.startswith("#")]

reader = csv.DictReader(lines, delimiter="\t")
cols = reader.fieldnames or []

if not cols:
    raise SystemExit("[ERROR] report header 없음")

sample_col = None
for c in cols:
    cl = c.lower()
    if "cel" in cl or "sample" in cl:
        sample_col = c
        break
if sample_col is None:
    sample_col = cols[0]

call_col = None
for c in cols:
    cl = c.lower()
    if "call" in cl and "rate" in cl:
        call_col = c
        break

if call_col is None:
    raise SystemExit("[ERROR] call rate 컬럼을 찾지 못했습니다. header=" + ",".join(cols))

raw = []
vals = []

for r in reader:
    sample = r.get(sample_col, "")
    key = norm_key(sample)
    cel_path = cel_by_key.get(key, sample)

    try:
        val = float(r.get(call_col, "nan"))
    except Exception:
        val = -1.0

    raw.append([sample, key, cel_path, val])
    if val >= 0:
        vals.append(val)

max_val = max(vals) if vals else 0
threshold = threshold_raw / 100.0 if max_val <= 1.5 and threshold_raw > 1.5 else threshold_raw

passed = []
rows = []

for sample, key, cel_path, val in raw:
    status = "PASS" if val >= threshold else "FAIL"
    rows.append([sample, key, cel_path, str(val), status])
    if status == "PASS":
        passed.append(cel_path)

with open(pass_out, "w", encoding="utf-8") as out:
    out.write("cel_files\n")
    for x in passed:
        out.write(x + "\n")

with open(summary_out, "w", encoding="utf-8") as out:
    out.write("sample\tsample_key\tcel_path\tcall_rate\tCALLRATE_STATUS\n")
    for r in rows:
        out.write("\t".join(r) + "\n")

print("[OK] Total:", len(rows))
print("[OK] Call Rate PASS:", len(passed))
print("[OK] Call Rate FAIL:", len(rows) - len(passed))
print("[OK] threshold used:", threshold)

PY

echo "[OK] QC Call Rate PASS list 생성 완료"
