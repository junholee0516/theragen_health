#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG="${1:?run_config.sh 필요}"
source "$CONFIG"

echo "============================================================"
echo "[03] DishQC PASS list 생성"
echo "============================================================"

mkdir -p "$(dirname "$DISH_PASS_LIST")" "$FINAL_DIR"

REPORT="$(find "$DISHQC_DIR" -type f \( -iname "*report.txt" -o -iname "*qc*.txt" \) 2>/dev/null | sort | head -1 || true)"

if [ -z "$REPORT" ] || [ ! -f "$REPORT" ]; then
  echo "[ERROR] DishQC report 파일을 찾지 못했습니다: $DISHQC_DIR"
  find "$DISHQC_DIR" -maxdepth 3 -type f | sort || true
  exit 1
fi

python3 - "$REPORT" "$CEL_LIST" "$DISH_PASS_LIST" "${FINAL_DIR}/DishQC_summary.tsv" "$DQC_THRESHOLD" <<'PY'
import sys, csv, os, re

report, cel_list, pass_out, summary_out, threshold = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], float(sys.argv[5])

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
    raise SystemExit("[ERROR] DishQC report header 없음")

def find_col(words):
    for c in cols:
        cl = c.lower()
        ok = True
        for w in words:
            if w.lower() not in cl:
                ok = False
                break
        if ok:
            return c
    return None

sample_col = None
for c in cols:
    if "cel" in c.lower() or "sample" in c.lower():
        sample_col = c
        break
if sample_col is None:
    sample_col = cols[0]

dqc_col = find_col(["dish"]) or find_col(["dqc"]) or find_col(["qc"])

if dqc_col is None:
    raise SystemExit("[ERROR] DishQC/DQC 컬럼을 찾지 못했습니다. header=" + ",".join(cols))

rows = []
passed = []

for r in reader:
    sample = r.get(sample_col, "")
    key = norm_key(sample)
    cel_path = cel_by_key.get(key, sample)

    try:
        dqc = float(r.get(dqc_col, "nan"))
    except Exception:
        dqc = -1.0

    status = "PASS" if dqc >= threshold else "FAIL"
    rows.append([sample, key, cel_path, str(dqc), status])

    if status == "PASS":
        passed.append(cel_path)

with open(pass_out, "w", encoding="utf-8") as out:
    out.write("cel_files\n")
    for x in passed:
        out.write(x + "\n")

with open(summary_out, "w", encoding="utf-8") as out:
    out.write("sample\tsample_key\tcel_path\tdishqc\tDISHQC_STATUS\n")
    for r in rows:
        out.write("\t".join(r) + "\n")

print("[OK] Total:", len(rows))
print("[OK] DishQC PASS:", len(passed))
print("[OK] DishQC FAIL:", len(rows) - len(passed))
print("[OK] summary:", summary_out)
print("[OK] pass list:", pass_out)
PY
