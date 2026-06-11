#!/usr/bin/env bash
set -euo pipefail

CONFIG="${1:?run_config.sh 필요}"
source "$CONFIG"

echo "============================================================"
echo "[09] AxAS Copy Number Discovery batch folder 생성"
echo "============================================================"

AXAS_DIR="$OUT/AxAS_Copy_Number_Discovery_batch_$RUN_NAME"
AAS_DATA="$AXAS_DIR/AxiomAnalysisSuiteData"

SRC_07="$OUT/07_discovery_hmm/CNData"
SRC_TEMP="$OUT/Temp"

mkdir -p "$AXAS_DIR"
mkdir -p "$AAS_DATA"
mkdir -p "$AXAS_DIR/CNData"
mkdir -p "$AXAS_DIR/Temp"
mkdir -p "$AXAS_DIR/Logs"
mkdir -p "$AXAS_DIR/QC"
mkdir -p "$AXAS_DIR/snpLists"

echo "[INFO] RUN_NAME=$RUN_NAME"
echo "[INFO] CEL_DIR=${CEL_DIR:-}"
echo "[INFO] CEL_LIST=${CEL_LIST:-}"
echo "[INFO] AXAS_DIR=$AXAS_DIR"

echo
echo "[1] AxiomAnalysisSuiteData template 복사"
if [ -d "$TEMPLATE_FILES_DIR/AxiomAnalysisSuiteData" ]; then
  cp -a "$TEMPLATE_FILES_DIR/AxiomAnalysisSuiteData/." "$AAS_DATA/" || true
fi

echo
echo "[2] CNData 복사"
if [ ! -s "$SRC_07/AxiomHMM.cnv.a5" ]; then
  echo "[ERROR] AxiomHMM.cnv.a5 없음: $SRC_07/AxiomHMM.cnv.a5"
  exit 1
fi

if [ ! -s "$SRC_07/AxiomHMM.report.txt" ]; then
  echo "[ERROR] AxiomHMM.report.txt 없음: $SRC_07/AxiomHMM.report.txt"
  exit 1
fi

cp -f "$SRC_07/AxiomHMM.cnv.a5" "$AXAS_DIR/CNData/AxiomHMM.cnv.a5"
cp -f "$SRC_07/AxiomHMM.report.txt" "$AXAS_DIR/CNData/AxiomHMM.report.txt"

echo
echo "[3] Temp 파일 복사"
for f in CopyNumber.APT2Input GenoTyping.APT2Input ChangedSCAxiom_PangenomiX.r1.apt-genotype-axiom.AxiomCN_GT1.apt2.xml; do
  found=""
  for d in "$SRC_TEMP" "$OUT/Temp" "$TEMPLATE_FILES_DIR/Temp"; do
    if [ -s "$d/$f" ]; then
      found="$d/$f"
      break
    fi
  done

  if [ -n "$found" ]; then
    cp -f "$found" "$AXAS_DIR/Temp/$f"
    echo "[OK] $f copied"
  else
    echo "[WARN] $f 없음"
  fi
done

echo
echo "[4] root AxiomGT1.* 제거"
rm -f "$AXAS_DIR"/AxiomGT1.calls.txt
rm -f "$AXAS_DIR"/AxiomGT1.confidences.txt
rm -f "$AXAS_DIR"/AxiomGT1.report.txt
rm -f "$AXAS_DIR"/AxiomGT1.summary.a5

echo
echo "[5] 현재 CEL_LIST 기준 AxAS metadata 생성"

CEL_LIST_FOR_AXAS=""
for f in "${CEL_LIST:-}" "$OUT/01_input/cel_list.txt" "$OUT/input/cel_list.txt" "$OUT/cel_list.txt"; do
  if [ -n "$f" ] && [ -s "$f" ]; then
    CEL_LIST_FOR_AXAS="$f"
    break
  fi
done

if [ -z "$CEL_LIST_FOR_AXAS" ]; then
  echo "[ERROR] CEL list 없음"
  echo "CEL_LIST=${CEL_LIST:-}"
  echo "OUT=$OUT"
  exit 1
fi

python3 - "$CEL_LIST_FOR_AXAS" "$AXAS_DIR" "$AAS_DATA" "$TEMPLATE_FILES_DIR" "${CEL_DIR:-}" "$RUN_NAME" <<'PY'
from __future__ import print_function
import sys
import os
import re
import csv
import uuid
import struct
import hashlib
from datetime import datetime

cel_list_file = sys.argv[1]
axas_dir = sys.argv[2]
aas_data = sys.argv[3]
template_dir = sys.argv[4]
cel_dir = sys.argv[5]
run_name = sys.argv[6]

genotyping_file = os.path.join(axas_dir, "genotyping_cel_files.txt")
sample_info_bin = os.path.join(aas_data, "sample_info.bin")
cel_headers_out = os.path.join(aas_data, "cel_headers.txt")
hmm_report = os.path.join(axas_dir, "CNData", "AxiomHMM.report.txt")

template_cel_headers = os.path.join(template_dir, "AxiomAnalysisSuiteData", "cel_headers.txt")
template_genotyping = os.path.join(template_dir, "genotyping_cel_files.txt")

sample_fields = [
    "cel_files",
    "affymetrix-plate-barcode",
    "affymetrix-plate-peg-wellposition",
    "cel_filepath",
    "cel_file_identifier",
    "affymetrix-array-id",
]

def clean_line(x):
    x = x.strip()
    if x.startswith(u"\ufeff"):
        x = x.lstrip(u"\ufeff")
    return x

def basename_sample(x):
    return str(x).replace("\\", "/").split("/")[-1]

def detect_windows_prefix():
    # AxAS용 genotyping_cel_files.txt는 Windows-style path를 사용함.
    # Demo Data 경로는 하드코딩하지 않고 RUN_NAME 기반으로 생성.
    # 필요하면 실행 전에 AXAS_WINDOWS_CEL_PREFIX 환경변수로 지정 가능.
    bs = chr(92)

    env = os.environ.get("AXAS_WINDOWS_CEL_PREFIX", "").strip()

    if env:
        env = env.replace("/", bs)
        if not env.endswith(bs):
            env += bs
        return env

    safe_run = re.sub(r"[^A-Za-z0-9_.-]+", "_", run_name)

    return (
        "C:" + bs +
        "Users" + bs +
        "Public" + bs +
        "Documents" + bs +
        "AxiomAnalysisSuite" + bs +
        safe_run + bs
    )


def extract_well_from_name(name):
    base = basename_sample(name)
    stem = os.path.splitext(base)[0]

    # 가장 중요한 규칙:
    # NA11882_Axiom_PangenomiX_Plus_A04.CEL 에서
    # NA11882 안의 A11이 아니라, 맨 뒤 suffix A04만 잡아야 함.
    m = re.search(r'(?:^|[_\-.])([A-P](?:0[1-9]|1[0-9]|2[0-4]))$', stem, re.I)
    if m:
        return m.group(1).upper()

    # 혹시 확장자 제거 후 token이 분리되어 있으면 마지막 well token만 사용
    tokens = re.split(r'[_\-.]+', stem)
    for token in reversed(tokens):
        if re.match(r'^[A-P](?:0[1-9]|1[0-9]|2[0-4])$', token, re.I):
            return token.upper()

    return None

def guess_well(name, idx):
    well = extract_well_from_name(name)
    if well:
        return well

    # filename에서 well을 못 찾을 때만 순서 기반 fallback
    # AxAS plate view는 A-P / 1-24 형태를 쓸 수 있으므로 16x24 기준
    rows = "ABCDEFGHIJKLMNOP"
    r = rows[(idx // 24) % 16]
    c = (idx % 24) + 1
    return "{}{:02d}".format(r, c)

def guess_plate(name, run_name):
    # 예전 로직은 NA11882에서 N + A11로 잘못 분리했음.
    # CEL header에서 plate barcode를 못 읽을 때는 filename을 억지로 자르지 말고 RUN_NAME을 사용.
    return run_name


def stable_uuid(base, salt):
    return str(uuid.uuid5(uuid.NAMESPACE_DNS, base + "_" + salt))

def stable_identifier(base, salt):
    h = hashlib.sha256((base + "_" + salt).encode("utf-8")).hexdigest()
    return "{}-{}-{}-{}-{}".format(
        h[0:10],
        h[10:20],
        h[20:27],
        h[27:34],
        h[34:41],
    )

def read_cel_list(path):
    out = []
    with open(path, "r") as f:
        for raw in f:
            line = clean_line(raw)

            if not line:
                continue
            if line.startswith("#"):
                continue
            if line.lower() == "cel_files":
                continue

            if "\t" in line:
                line = line.split("\t")[0].strip()

            if "/" not in line and "\\" not in line and cel_dir:
                candidate = os.path.join(cel_dir, line)
                if os.path.exists(candidate):
                    line = candidate

            out.append(line)

    return out

def read_template_cel_header():
    if not os.path.exists(template_cel_headers):
        fields = [
            "cel_files",
            "affymetrix-array-id",
            "affymetrix-array-barcode",
            "affymetrix-scan-date",
            "affymetrix-created-trackingGUID",
            "affymetrix-parent-dat-file-identifier",
            "affymetrix-plate-barcode",
            "affymetrix-plate-peg-wellposition",
            "affymetrix-scanner-id",
            "affymetrix-scanner-type",
            "plateRows",
            "plateColumns",
            "cel_filepath",
            "cel_file_identifier",
        ]
        return fields, {}, {}

    with open(template_cel_headers, "r") as f:
        reader = csv.DictReader(f, delimiter="\t")
        fields = reader.fieldnames or []
        first = {}
        by_well = {}

        for row in reader:
            if not first:
                first = dict(row)
            well = row.get("affymetrix-plate-peg-wellposition", "")
            if well:
                by_well[well.upper()] = dict(row)

    for req in [
        "cel_files",
        "affymetrix-array-id",
        "affymetrix-array-barcode",
        "affymetrix-plate-barcode",
        "affymetrix-plate-peg-wellposition",
        "cel_filepath",
        "cel_file_identifier",
    ]:
        if req not in fields:
            fields.append(req)

    return fields, first, by_well

def read_cel_header_values(cel_path):
    values = {}

    keys = [
        "affymetrix-array-id",
        "affymetrix-array-barcode",
        "affymetrix-plate-barcode",
        "affymetrix-plate-peg-wellposition",
        "affymetrix-created-trackingGUID",
        "affymetrix-parent-dat-file-identifier",
        "affymetrix-file-identifier",
        "affymetrix-created-file-identifier",
        "cel_file_identifier",
        "affymetrix-scan-date",
        "affymetrix-workflowGUID",
        "affymetrix-PlateScanGUID",
        "affymetrix-scanner-serialnumber",
    ]

    try:
        with open(cel_path, "rb") as f:
            data = f.read(5 * 1024 * 1024)
        text = data.decode("latin1", errors="ignore")
    except Exception:
        return values

    for key in keys:
        patterns = [
            re.escape(key) + r"\s*=\s*([^\r\n\t;]+)",
            re.escape(key) + r"\s*:\s*([^\r\n\t;]+)",
        ]

        for pat in patterns:
            m = re.search(pat, text, re.I)
            if m:
                v = m.group(1).strip().strip('"').strip("'")
                if v:
                    values[key] = v
                    break

    return values

def write7(f, value):
    value = int(value)
    while value >= 0x80:
        f.write(bytes([(value | 0x80) & 0xff]))
        value >>= 7
    f.write(bytes([value & 0xff]))

def write_string(f, s):
    if s is None:
        s = ""
    b = str(s).encode("utf-8")
    write7(f, len(b))
    f.write(b)

def write_sample_info_bin(path, rows):
    with open(path, "wb") as f:
        f.write(struct.pack("<I", len(rows)))

        for field in sample_fields:
            write_string(f, field)

        for row in rows:
            for field in sample_fields:
                write_string(f, row.get(field, ""))

def validate_sample_info(path, expected_count):
    data = open(path, "rb").read()

    count = struct.unpack("<I", data[:4])[0]
    if count != expected_count:
        raise SystemExit("[ERROR] sample_info.bin count mismatch: {} != {}".format(count, expected_count))

    if data[4:14] != b"\tcel_files":
        raise SystemExit("[ERROR] sample_info.bin header invalid: {}".format(data[:40]))

def normalize_hmm_report(path, sample_rows):
    if not os.path.exists(path):
        return

    lines = open(path, "r").read().splitlines()

    header_idx = None
    header = None

    for i, line in enumerate(lines):
        if not line.strip():
            continue
        if line.startswith("#"):
            continue
        if "\t" not in line:
            continue
        parts = line.split("\t")
        if "cel_files" in parts:
            header_idx = i
            header = parts
            break

    if header_idx is None:
        return

    idx = {}
    for key in [
        "cel_files",
        "affymetrix-plate-barcode",
        "affymetrix-plate-peg-wellposition",
    ]:
        if key in header:
            idx[key] = header.index(key)

    if "cel_files" not in idx:
        return

    by_base = {}
    for row in sample_rows:
        by_base[row["cel_files"]] = row

    out = list(lines)
    row_i = 0

    for i in range(header_idx + 1, len(lines)):
        line = lines[i]

        if not line.strip() or line.startswith("#") or "\t" not in line:
            continue

        parts = line.split("\t")

        if len(parts) <= idx["cel_files"]:
            continue

        base = basename_sample(parts[idx["cel_files"]])
        sample_row = by_base.get(base)

        if sample_row is None and row_i < len(sample_rows):
            sample_row = sample_rows[row_i]

        if sample_row is not None:
            parts[idx["cel_files"]] = sample_row["cel_files"]

            if "affymetrix-plate-barcode" in idx and len(parts) > idx["affymetrix-plate-barcode"]:
                parts[idx["affymetrix-plate-barcode"]] = sample_row["affymetrix-plate-barcode"]

            if "affymetrix-plate-peg-wellposition" in idx and len(parts) > idx["affymetrix-plate-peg-wellposition"]:
                parts[idx["affymetrix-plate-peg-wellposition"]] = sample_row["affymetrix-plate-peg-wellposition"]

            out[i] = "\t".join(parts)

        row_i += 1

    with open(path, "w") as f:
        f.write("\n".join(out) + "\n")

cel_paths = read_cel_list(cel_list_file)

if not cel_paths:
    raise SystemExit("[ERROR] CEL list가 비어 있습니다.")

windows_prefix = detect_windows_prefix()
template_fields, template_first, template_by_well = read_template_cel_header()

sample_rows = []
cel_header_rows = []

for idx, cel_path in enumerate(cel_paths):
    base = basename_sample(cel_path)
    h = read_cel_header_values(cel_path)

    well = h.get("affymetrix-plate-peg-wellposition") or guess_well(base, idx)

    plate = (
        h.get("affymetrix-plate-barcode") or
        h.get("affymetrix-array-barcode") or
        guess_plate(base, run_name)
    )

    array_id = h.get("affymetrix-array-id") or stable_uuid(base, "array_id")

    cel_file_identifier = (
        h.get("cel_file_identifier") or
        h.get("affymetrix-file-identifier") or
        h.get("affymetrix-created-file-identifier") or
        stable_identifier(base, "cel_file_identifier")
    )

    win_path = windows_prefix + base

    sample_row = {
        "cel_files": base,
        "affymetrix-plate-barcode": plate,
        "affymetrix-plate-peg-wellposition": well,
        "cel_filepath": win_path,
        "cel_file_identifier": cel_file_identifier,
        "affymetrix-array-id": array_id,
    }

    sample_rows.append(sample_row)

    row_template = template_by_well.get(well, template_first)
    ch = {}

    for field in template_fields:
        ch[field] = row_template.get(field, "")

    overrides = {
        "cel_files": base,
        "affymetrix-array-id": array_id,
        "affymetrix-array-barcode": plate,
        "affymetrix-plate-barcode": plate,
        "affymetrix-plate-peg-wellposition": well,
        "cel_filepath": win_path,
        "cel_file_identifier": cel_file_identifier,
        "affymetrix-file-identifier": cel_file_identifier,
        "affymetrix-created-file-identifier": cel_file_identifier,
        "affymetrix-created-trackingGUID": h.get("affymetrix-created-trackingGUID") or stable_identifier(base, "created_trackingGUID"),
        "affymetrix-parent-dat-file-identifier": h.get("affymetrix-parent-dat-file-identifier") or stable_identifier(base, "parent_dat_file_identifier"),
        "affymetrix-workflowGUID": h.get("affymetrix-workflowGUID") or stable_uuid(base, "workflowGUID"),
        "affymetrix-PlateScanGUID": h.get("affymetrix-PlateScanGUID") or "{}_{}".format(plate, run_name),
        "affymetrix-scan-date": h.get("affymetrix-scan-date") or datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
    }

    for k, v in overrides.items():
        if k in ch:
            ch[k] = v

    cel_header_rows.append(ch)

# 정답 형식: genotyping_cel_files.txt는 1컬럼 path list
with open(genotyping_file, "wb") as f:
    lines = ["cel_files"]
    for row in sample_rows:
        lines.append(row["cel_filepath"])
    f.write(("\r\n".join(lines) + "\r\n").encode("utf-8"))

# 정답 형식: cel_headers.txt는 긴 metadata table
with open(cel_headers_out, "wb") as f:
    lines = []
    lines.append("\t".join(template_fields))

    for row in cel_header_rows:
        lines.append("\t".join(row.get(c, "") for c in template_fields))

    f.write(("\r\n".join(lines) + "\r\n").encode("utf-8"))

# 정답 형식: sample_info.bin은 binary count + 6 header strings + rows
write_sample_info_bin(sample_info_bin, sample_rows)
validate_sample_info(sample_info_bin, len(sample_rows))

# HMM report 안의 sample / plate / well도 현재 sample metadata와 맞춤
normalize_hmm_report(hmm_report, sample_rows)

print("[OK] current CEL sample metadata generated")
print("[OK] CEL count = {}".format(len(sample_rows)))
print("[OK] windows_prefix = {}".format(windows_prefix))
print("[OK] genotyping_cel_files.txt = {}".format(genotyping_file))
print("[OK] cel_headers.txt = {}".format(cel_headers_out))
print("[OK] sample_info.bin = {}".format(sample_info_bin))
PY

echo
echo "[CHECK] genotyping_cel_files.txt"
head -n 5 "$AXAS_DIR/genotyping_cel_files.txt" | cat -A
awk 'NR==1{print "HEADER="$0}' "$AXAS_DIR/genotyping_cel_files.txt"

echo
echo "[CHECK] sample_info.bin"
python3 - "$AAS_DATA/sample_info.bin" <<'PY'
from __future__ import print_function
import sys, struct
data=open(sys.argv[1],"rb").read()
count=struct.unpack("<I", data[:4])[0]
print("sample_count={}".format(count))
print("first20={}".format(data[:20]))
if data[4:14] != b"\tcel_files":
    raise SystemExit("[ERROR] sample_info.bin format invalid")
print("[OK] sample_info.bin correct")
PY

echo
echo "[CHECK] cel_headers.txt"
head -n 2 "$AAS_DATA/cel_headers.txt" | cat -A
head -n 1 "$AAS_DATA/cel_headers.txt" | awk -F '\t' '{print "cel_headers_NF="NF}'

echo
echo "[6] Logs 복사"
if [ -d "$OUT/logs" ]; then
  cp -a "$OUT/logs/." "$AXAS_DIR/Logs/" || true
fi

echo
echo "[7] checksum 확인"
sha256sum "$SRC_07/AxiomHMM.cnv.a5" "$AXAS_DIR/CNData/AxiomHMM.cnv.a5"
sha256sum "$SRC_07/AxiomHMM.report.txt" "$AXAS_DIR/CNData/AxiomHMM.report.txt"

echo
echo "[DONE] AxAS batch folder 생성 완료"
echo "[DONE] $AXAS_DIR"
