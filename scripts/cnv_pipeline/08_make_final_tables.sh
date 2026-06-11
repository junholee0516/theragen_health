#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG="${1:?run_config.sh 필요}"
source "$CONFIG"

echo "============================================================"
echo "[08] 최종 CNV 위치표 및 샘플별 개수표 생성 - QC PASS 샘플만"
echo "============================================================"

mkdir -p "$FINAL_DIR"

CNV_A5="$(find "$HMM_DIR" -maxdepth 4 -type f -name "AxiomHMM.cnv.a5" | sort | head -1 || true)"
if [ -z "$CNV_A5" ]; then
  CNV_A5="$(find "$HMM_DIR" -maxdepth 4 -type f -name "*.cnv.a5" | sort | head -1 || true)"
fi

HMM_REPORT="$(find "$HMM_DIR" -maxdepth 4 -type f \( \
  -name "AxiomHMM.report.txt" -o \
  -name "AxiomHMM.report" -o \
  -name "*.report.txt" -o \
  -name "*.report" \
\) | sort | head -1 || true)"

PASS_LIST="${QC_PASS_LIST:-}"
if [ -z "$PASS_LIST" ] || [ ! -f "$PASS_LIST" ]; then
  PASS_LIST="${CALLRATE_PASS_LIST:-}"
fi

ANNOT_DB="${ANNOT_DB:-}"
if [ -z "$ANNOT_DB" ] || [ ! -f "$ANNOT_DB" ]; then
  ANNOT_DB="$(find "$LIB_DIR" -maxdepth 2 -type f -iname "*.annot.db" | sort | head -1 || true)"
fi

VCF_FILE="${FINAL_DIR}/AxiomHMM_discovery_segments.txt"

echo "[INFO] HMM_DIR    = $HMM_DIR"
echo "[INFO] FINAL_DIR  = $FINAL_DIR"
echo "[INFO] CNV_A5     = $CNV_A5"
echo "[INFO] HMM_REPORT = $HMM_REPORT"
echo "[INFO] PASS_LIST  = $PASS_LIST"
echo "[INFO] APT_FORMAT = $APT_FORMAT"
echo "[INFO] ANNOT_DB   = $ANNOT_DB"
echo "[INFO] VCF_FILE   = $VCF_FILE"

if [ -z "$CNV_A5" ] || [ ! -f "$CNV_A5" ]; then
  echo "[ERROR] AxiomHMM.cnv.a5 파일을 찾지 못했습니다."
  find "$HMM_DIR" -maxdepth 4 -type f | sort || true
  exit 1
fi

if [ -z "$PASS_LIST" ] || [ ! -f "$PASS_LIST" ]; then
  echo "[ERROR] QC PASS list 파일을 찾지 못했습니다."
  echo "[ERROR] QC_PASS_LIST       = ${QC_PASS_LIST:-}"
  echo "[ERROR] CALLRATE_PASS_LIST = ${CALLRATE_PASS_LIST:-}"
  exit 1
fi

if [ -z "$APT_FORMAT" ] || [ ! -f "$APT_FORMAT" ]; then
  echo "[ERROR] apt-format-result 실행파일을 찾지 못했습니다."
  echo "[ERROR] APT_FORMAT = $APT_FORMAT"
  exit 1
fi

if [ -z "$ANNOT_DB" ] || [ ! -f "$ANNOT_DB" ]; then
  echo "[ERROR] annotation db 파일을 찾지 못했습니다."
  echo "[CHECK] LIB_DIR = $LIB_DIR"
  find "$LIB_DIR" -maxdepth 2 -type f | grep -i "annot.db" || true
  exit 1
fi

echo ""
echo "[CHECK] QC PASS sample 수"
grep -v '^#' "$PASS_LIST" | grep -v '^$' | grep -v '^cel_files$' | wc -l

echo ""
echo "[1] AxiomHMM.cnv.a5 → VCF export"
"$APT_FORMAT" \
  --cn-region-calls-file "$CNV_A5" \
  --annotation-file "$ANNOT_DB" \
  --export-chr-shortname true \
  --export-vcf-file "$VCF_FILE"

if [ ! -f "$VCF_FILE" ]; then
  echo "[ERROR] VCF export 결과가 없습니다."
  exit 1
fi

echo "[OK] VCF export 완료"
ls -lh "$VCF_FILE"

echo ""
echo "[2] VCF → QC PASS sample만 final TSV 5종 생성"

python3 - "$VCF_FILE" "$HMM_REPORT" "$FINAL_DIR" "$PASS_LIST" <<'PY'
import sys
import os
import csv
from collections import defaultdict

vcf = sys.argv[1]
hmm_report = sys.argv[2]
final_dir = sys.argv[3]
pass_list = sys.argv[4]

all_out = os.path.join(final_dir, "Discovery_CNV_all_segments.tsv")
abn_out = os.path.join(final_dir, "Discovery_CNV_abnormal_segments.tsv")
sample_count_out = os.path.join(final_dir, "Discovery_CNV_sample_count.tsv")
region_count_out = os.path.join(final_dir, "Discovery_CNV_region_count.tsv")
hmm_qc_out = os.path.join(final_dir, "Discovery_HMM_QC_summary.tsv")

def norm_sample(x):
    x = str(x).strip().replace("\\", "/")
    x = x.split("/")[-1]
    if x.lower().endswith(".cel"):
        x = x[:-4]
    return x

def display_sample(x):
    x = str(x).strip().replace("\\", "/")
    x = x.split("/")[-1]
    return x

def parse_info(info):
    d = {}
    for item in info.split(";"):
        item = item.strip()
        if not item:
            continue
        if "=" in item:
            k, v = item.split("=", 1)
            d[k] = v
        else:
            d[item] = ""
    return d

def chrom_key(c):
    c = str(c).replace("chr", "")
    if c == "X":
        return 23
    if c == "Y":
        return 24
    try:
        return int(c)
    except Exception:
        return 99

def cn_interpretation(cn):
    try:
        cn = int(cn)
    except Exception:
        return "unknown"
    if cn == 0:
        return "homozygous_deletion_candidate"
    if cn == 1:
        return "deletion_candidate"
    if cn == 3:
        return "duplication_gain_candidate"
    if cn >= 4:
        return "amplification_candidate"
    return "non_CN2_candidate"

# QC PASS sample set
pass_set = set()
pass_display = {}

with open(pass_list, encoding="utf-8", errors="replace") as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if line.lower() == "cel_files":
            continue
        first = line.split("\t")[0].split(",")[0].strip()
        ns = norm_sample(first)
        if ns:
            pass_set.add(ns)
            pass_display[ns] = display_sample(first)

if not pass_set:
    sys.stderr.write("[ERROR] QC PASS sample list가 비어 있습니다.\n")
    sys.exit(1)

vcf_samples = []
pass_sample_indices = []
records = []

with open(vcf, encoding="utf-8", errors="replace") as f:
    for line in f:
        line = line.rstrip("\n\r")
        if not line:
            continue

        if line.startswith("#CHROM"):
            header = line.lstrip("#").split("\t")
            vcf_samples = header[9:]
            pass_sample_indices = []
            for i, s in enumerate(vcf_samples):
                if norm_sample(s) in pass_set:
                    pass_sample_indices.append(i)
            continue

        if line.startswith("#"):
            continue

        parts = line.split("\t")
        if len(parts) < 10:
            continue

        chrom = parts[0].replace("chr", "")
        start = parts[1]
        info = parse_info(parts[7])
        end = info.get("END", start)

        try:
            size_bp = str(int(end) - int(start) + 1)
        except Exception:
            size_bp = ""

        fmt = parts[8].split(":")
        sample_values = parts[9:]

        for idx in pass_sample_indices:
            if idx >= len(sample_values):
                continue

            sample_raw = vcf_samples[idx]
            sample_name = display_sample(sample_raw)
            value = sample_values[idx]

            if value in ["", ".", "./."]:
                continue

            vals = value.split(":")
            cn = ""

            if "CN" in fmt:
                cn_idx = fmt.index("CN")
                if cn_idx < len(vals):
                    cn = vals[cn_idx]
            else:
                cn = vals[0]

            if cn in ["", "."]:
                continue

            try:
                cn_int = int(float(cn))
            except Exception:
                continue

            records.append({
                "sample": sample_name,
                "chromosome": chrom,
                "start": start,
                "end": end,
                "size_bp": size_bp,
                "CN_state": str(cn_int)
            })

if not records:
    sys.stderr.write("[ERROR] VCF에서 QC PASS sample의 CNV segment record를 읽지 못했습니다.\n")
    sys.stderr.write("[CHECK] VCF = {}\n".format(vcf))
    sys.stderr.write("[CHECK] PASS_LIST = {}\n".format(pass_list))
    sys.exit(1)

records.sort(key=lambda x: (
    x["sample"],
    chrom_key(x["chromosome"]),
    int(x["start"]),
    int(x["end"]),
    int(x["CN_state"])
))

# all segments
with open(all_out, "w", encoding="utf-8") as out:
    out.write("sample\tchromosome\tstart\tend\tsize_bp\tCN_state\n")
    for r in records:
        out.write("{sample}\t{chromosome}\t{start}\t{end}\t{size_bp}\t{CN_state}\n".format(**r))

# abnormal
abnormal = [r for r in records if r["CN_state"] != "2"]

with open(abn_out, "w", encoding="utf-8") as out:
    out.write("sample\tchromosome\tstart\tend\tsize_bp\tCN_state\tinterpretation\n")
    for r in abnormal:
        out.write("{sample}\t{chromosome}\t{start}\t{end}\t{size_bp}\t{CN_state}\t{interp}\n".format(
            sample=r["sample"],
            chromosome=r["chromosome"],
            start=r["start"],
            end=r["end"],
            size_bp=r["size_bp"],
            CN_state=r["CN_state"],
            interp=cn_interpretation(r["CN_state"])
        ))

# sample count: QC PASS sample만
summary = {}
for ns in pass_set:
    s = pass_display.get(ns, ns + ".CEL")
    summary[s] = {
        "CN0": 0,
        "CN1": 0,
        "CN2": 0,
        "CN3": 0,
        "CN4plus": 0,
        "abnormal": 0,
        "all": 0
    }

for r in records:
    s = r["sample"]
    cn = int(r["CN_state"])

    if s not in summary:
        summary[s] = {
            "CN0": 0,
            "CN1": 0,
            "CN2": 0,
            "CN3": 0,
            "CN4plus": 0,
            "abnormal": 0,
            "all": 0
        }

    summary[s]["all"] += 1

    if cn == 0:
        summary[s]["CN0"] += 1
    elif cn == 1:
        summary[s]["CN1"] += 1
    elif cn == 2:
        summary[s]["CN2"] += 1
    elif cn == 3:
        summary[s]["CN3"] += 1
    elif cn >= 4:
        summary[s]["CN4plus"] += 1

    if cn != 2:
        summary[s]["abnormal"] += 1

with open(sample_count_out, "w", encoding="utf-8") as out:
    out.write("sample\tCN0_count\tCN1_count\tCN2_count\tCN3_count\tCN4plus_count\tabnormal_CNV_count\tall_segment_count\n")
    for s in sorted(summary, key=lambda x: (-summary[x]["abnormal"], x)):
        v = summary[s]
        out.write("{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\n".format(
            s,
            v["CN0"],
            v["CN1"],
            v["CN2"],
            v["CN3"],
            v["CN4plus"],
            v["abnormal"],
            v["all"]
        ))

# region count: QC PASS sample 중 abnormal만
region_summary = defaultdict(list)

for r in abnormal:
    key = (
        r["chromosome"],
        r["start"],
        r["end"],
        r["size_bp"],
        r["CN_state"]
    )
    region_summary[key].append(r["sample"])

with open(region_count_out, "w", encoding="utf-8") as out:
    out.write("chromosome\tstart\tend\tsize_bp\tCN_state\tsample_count\tsamples\n")
    for key in sorted(region_summary, key=lambda k: (chrom_key(k[0]), int(k[1]), int(k[2]), int(k[4]))):
        chrom, start, end, size_bp, cn = key
        sample_list = sorted(region_summary[key])
        out.write("{}\t{}\t{}\t{}\t{}\t{}\t{}\n".format(
            chrom,
            start,
            end,
            size_bp,
            cn,
            len(sample_list),
            ",".join(sample_list)
        ))

# HMM QC summary도 QC PASS sample만
if hmm_report and os.path.exists(hmm_report):
    with open(hmm_report, encoding="utf-8", errors="replace") as f:
        lines = [x for x in f if x.strip() and not x.startswith("#")]

    reader = csv.DictReader(lines, delimiter="\t")
    fields = reader.fieldnames or []

    keep = []
    for c in [
        "cel_files",
        "CN passes QC",
        "MAPD",
        "WavinessSD",
        "Count of CN 0 Segments",
        "Count of CN 1 Segments",
        "Count of CN 2 Segments",
        "Count of CN 3 Segments"
    ]:
        if c in fields:
            keep.append(c)

    with open(hmm_qc_out, "w", encoding="utf-8") as out:
        out.write("\t".join(keep) + "\n")
        for row in reader:
            sample = row.get("cel_files", "")
            if norm_sample(sample) not in pass_set:
                continue
            out.write("\t".join([row.get(c, "") for c in keep]) + "\n")
else:
    with open(hmm_qc_out, "w", encoding="utf-8") as out:
        out.write("cel_files\tCN passes QC\tMAPD\tWavinessSD\tCount of CN 0 Segments\tCount of CN 1 Segments\tCount of CN 2 Segments\tCount of CN 3 Segments\n")

print("[OK] QC PASS sample만 생성 완료")
print("[INFO] QC PASS sample count = {}".format(len(pass_set)))
print("[INFO] VCF PASS sample count = {}".format(len(pass_sample_indices)))
print(all_out)
print(abn_out)
print(sample_count_out)
print(region_count_out)
print(hmm_qc_out)
PY

echo ""
echo "[OK] 08_final_tables 생성 파일"
ls -lh "$FINAL_DIR"/Discovery_*.tsv
ls -lh "$VCF_FILE"

echo ""
echo "[DONE] 최종 CNV table 생성 완료 - QC PASS 샘플만"
