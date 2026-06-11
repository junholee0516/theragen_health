#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG="${1:?run_config.sh 필요}"
source "$CONFIG"

SCRIPT_DIR_SELF="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR_SELF/../.." && pwd)"

echo "============================================================"
echo "[07] Discovery HMM 실행 - AxAS AxiomGT1 입력 자동 선택"
echo "============================================================"

: "${OUT:?OUT 변수가 필요합니다. run_config.sh 확인}"
: "${CEL_LIST:?CEL_LIST 변수가 필요합니다. run_config.sh 확인}"

RUN_NAME="${RUN_NAME:-$(basename "$OUT")}"
TEMPLATE_FILES_DIR="${TEMPLATE_FILES_DIR:-$PROJECT_DIR/input/axas_template_files}"

HMM_DIR="${HMM_DIR:-$OUT/07_discovery_hmm}"
CN_OUT="$HMM_DIR/CNData"
TEMP_DIR="${TEMP_DIR:-$OUT/Temp}"
LOG_DIR="${LOG_DIR:-$OUT/logs}"

mkdir -p "$HMM_DIR" "$CN_OUT" "$TEMP_DIR" "$LOG_DIR"

APT_HMM="${APT_HMM:-$PROJECT_DIR/bin/apt-copynumber-axiom-hmm}"

if [ ! -x "$APT_HMM" ]; then
  echo "[ERROR] apt-copynumber-axiom-hmm 실행파일이 없습니다:"
  echo "$APT_HMM"
  exit 1
fi

echo "[INFO] OUT                = $OUT"
echo "[INFO] RUN_NAME           = $RUN_NAME"
echo "[INFO] TEMPLATE_FILES_DIR = $TEMPLATE_FILES_DIR"
echo "[INFO] HMM_DIR            = $HMM_DIR"
echo "[INFO] CN_OUT             = $CN_OUT"
echo "[INFO] CEL_LIST           = $CEL_LIST"
echo "[INFO] APT_HMM            = $APT_HMM"

# ------------------------------------------------------------
# 1. AxiomGT1 4종 파일 위치 확인
# ------------------------------------------------------------

TEMPLATE_AXIOM_DIR="$TEMPLATE_FILES_DIR"

TEMPLATE_SUMMARY="$TEMPLATE_AXIOM_DIR/AxiomGT1.summary.a5"
TEMPLATE_REPORT="$TEMPLATE_AXIOM_DIR/AxiomGT1.report.txt"
TEMPLATE_CALLS="$TEMPLATE_AXIOM_DIR/AxiomGT1.calls.txt"
TEMPLATE_CONF="$TEMPLATE_AXIOM_DIR/AxiomGT1.confidences.txt"

find_current_file() {
  local name="$1"

  find \
    "$OUT/04_callrate" \
    "$OUT/03_callrate" \
    "$OUT" \
    -type f -name "$name" 2>/dev/null \
    | awk '!/AxAS_Copy_Number_Discovery_batch/ && !/input\/axas_template_files/ {print}' \
    | sort \
    | head -1
}

CURRENT_SUMMARY="$(find_current_file "AxiomGT1.summary.a5" || true)"
CURRENT_REPORT="$(find_current_file "AxiomGT1.report.txt" || true)"
CURRENT_CALLS="$(find_current_file "AxiomGT1.calls.txt" || true)"
CURRENT_CONF="$(find_current_file "AxiomGT1.confidences.txt" || true)"

echo ""
echo "[INFO] Template AxiomGT1"
ls -lh "$TEMPLATE_SUMMARY" "$TEMPLATE_REPORT" "$TEMPLATE_CALLS" "$TEMPLATE_CONF" 2>/dev/null || true

echo ""
echo "[INFO] Current run AxiomGT1"
[ -n "$CURRENT_SUMMARY" ] && ls -lh "$CURRENT_SUMMARY" || true
[ -n "$CURRENT_REPORT" ] && ls -lh "$CURRENT_REPORT" || true
[ -n "$CURRENT_CALLS" ] && ls -lh "$CURRENT_CALLS" || true
[ -n "$CURRENT_CONF" ] && ls -lh "$CURRENT_CONF" || true

# ------------------------------------------------------------
# 2. CEL 목록 일치 여부 확인
# ------------------------------------------------------------

compare_cel_list_with_report() {
  local cel_list="$1"
  local report="$2"

  python3 - "$cel_list" "$report" <<'PY'
import sys
import os

cel_list = sys.argv[1]
report = sys.argv[2]

def base(x):
    x = x.strip().replace("\\", "/")
    return x.split("/")[-1]

def read_cel_list(path):
    out = []
    with open(path, "r", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            if line.startswith("#"):
                continue
            if line.lower() == "cel_files":
                continue
            first = line.split("\t")[0].split(",")[0].strip()
            if first:
                out.append(base(first))
    return sorted(out)

def read_report_cels(path):
    out = []
    start = False

    with open(path, "r", errors="replace") as f:
        for line in f:
            line = line.rstrip("\n")
            if line.startswith("cel_files\t"):
                start = True
                continue

            if not start:
                continue

            if not line.strip():
                continue

            if line.startswith("#"):
                continue

            first = line.split("\t")[0].strip()
            if first:
                out.append(base(first))

    return sorted(out)

if not os.path.exists(report):
    print("NO")
    sys.exit(0)

a = read_cel_list(cel_list)
b = read_report_cels(report)

if a == b and len(a) > 0:
    print("YES")
else:
    print("NO")
    print("CEL_LIST_COUNT={}".format(len(a)), file=sys.stderr)
    print("REPORT_COUNT={}".format(len(b)), file=sys.stderr)
    only_a = sorted(set(a) - set(b))[:10]
    only_b = sorted(set(b) - set(a))[:10]
    if only_a:
        print("ONLY_IN_CEL_LIST={}".format(",".join(only_a)), file=sys.stderr)
    if only_b:
        print("ONLY_IN_REPORT={}".format(",".join(only_b)), file=sys.stderr)
PY
}

template_complete="no"
current_complete="no"
template_match="NO"
current_match="NO"

if [ -f "$TEMPLATE_SUMMARY" ] && [ -f "$TEMPLATE_REPORT" ] && [ -f "$TEMPLATE_CALLS" ] && [ -f "$TEMPLATE_CONF" ]; then
  template_complete="yes"
  template_match="$(compare_cel_list_with_report "$CEL_LIST" "$TEMPLATE_REPORT" | head -1)"
fi

if [ -n "$CURRENT_SUMMARY" ] && [ -n "$CURRENT_REPORT" ] && [ -n "$CURRENT_CALLS" ] && [ -n "$CURRENT_CONF" ] && \
   [ -f "$CURRENT_SUMMARY" ] && [ -f "$CURRENT_REPORT" ] && [ -f "$CURRENT_CALLS" ] && [ -f "$CURRENT_CONF" ]; then
  current_complete="yes"
  current_match="$(compare_cel_list_with_report "$CEL_LIST" "$CURRENT_REPORT" | head -1)"
fi

echo ""
echo "[CHECK] AxiomGT1 선택 조건"
echo "[CHECK] template_complete = $template_complete"
echo "[CHECK] template_match    = $template_match"
echo "[CHECK] current_complete  = $current_complete"
echo "[CHECK] current_match     = $current_match"

# ------------------------------------------------------------
# 3. 사용할 AxiomGT1 결정
# ------------------------------------------------------------

if [ "$template_complete" = "yes" ] && [ "$template_match" = "YES" ]; then
  AXIOMGT1_SOURCE="template_axas"
  SUMMARY_FILE="$TEMPLATE_SUMMARY"
  REPORT_FILE="$TEMPLATE_REPORT"
  LOH_CALLS_FILE="$TEMPLATE_CALLS"
  LOH_CONF_FILE="$TEMPLATE_CONF"

elif [ "$current_complete" = "yes" ] && [ "$current_match" = "YES" ]; then
  AXIOMGT1_SOURCE="current_run"
  SUMMARY_FILE="$CURRENT_SUMMARY"
  REPORT_FILE="$CURRENT_REPORT"
  LOH_CALLS_FILE="$CURRENT_CALLS"
  LOH_CONF_FILE="$CURRENT_CONF"

else
  echo ""
  echo "[ERROR] 현재 CEL 목록과 맞는 AxiomGT1 4종 파일을 찾지 못했습니다."
  echo ""
  echo "해결 방법:"
  echo "1) 새 CEL이면 먼저 04_callrate.sh가 새 CEL 기준 AxiomGT1.summary.a5/report/calls/confidences를 생성해야 합니다."
  echo "2) 현재 CEL과 같은 AxAS 원본 AxiomGT1 4종을 쓰려면 아래에 넣어야 합니다:"
  echo "   $TEMPLATE_FILES_DIR/AxiomGT1.summary.a5"
  echo "   $TEMPLATE_FILES_DIR/AxiomGT1.report.txt"
  echo "   $TEMPLATE_FILES_DIR/AxiomGT1.calls.txt"
  echo "   $TEMPLATE_FILES_DIR/AxiomGT1.confidences.txt"
  exit 1
fi

echo ""
echo "[INFO] 선택된 AxiomGT1 source = $AXIOMGT1_SOURCE"
echo "[INFO] SUMMARY_FILE   = $SUMMARY_FILE"
echo "[INFO] REPORT_FILE    = $REPORT_FILE"
echo "[INFO] LOH_CALLS_FILE = $LOH_CALLS_FILE"
echo "[INFO] LOH_CONF_FILE  = $LOH_CONF_FILE"

# ------------------------------------------------------------
# 4. HMM 입력 파일을 run 내부 안정 경로로 연결
# ------------------------------------------------------------

HMM_INPUT_DIR="$HMM_DIR/AxiomGT1_input"
rm -rf "$HMM_INPUT_DIR"
mkdir -p "$HMM_INPUT_DIR"

ln -sfn "$SUMMARY_FILE" "$HMM_INPUT_DIR/AxiomGT1.summary.a5"
ln -sfn "$REPORT_FILE" "$HMM_INPUT_DIR/AxiomGT1.report.txt"
ln -sfn "$LOH_CALLS_FILE" "$HMM_INPUT_DIR/AxiomGT1.calls.txt"
ln -sfn "$LOH_CONF_FILE" "$HMM_INPUT_DIR/AxiomGT1.confidences.txt"

SUMMARY_FILE="$HMM_INPUT_DIR/AxiomGT1.summary.a5"
REPORT_FILE="$HMM_INPUT_DIR/AxiomGT1.report.txt"
LOH_CALLS_FILE="$HMM_INPUT_DIR/AxiomGT1.calls.txt"
LOH_CONF_FILE="$HMM_INPUT_DIR/AxiomGT1.confidences.txt"

echo ""

# [FIX] For AxAS-equivalent LOH/HMZ, always use 06_cn_summary AxiomGT1 files.
# 04_callrate is QC/subset output and must not be used for HMM LOH.
SUMMARY_FILE="$OUT/06_cn_summary/AxiomGT1.summary.a5"
REPORT_FILE="$OUT/06_cn_summary/AxiomGT1.report.txt"
LOH_CALLS_FILE="$OUT/06_cn_summary/AxiomGT1.calls.txt"
LOH_CONF_FILE="$OUT/06_cn_summary/AxiomGT1.confidences.txt"
AXIOMGT1_SOURCE="current_06_cn_summary"

if [ ! -s "$SUMMARY_FILE" ] || [ ! -s "$REPORT_FILE" ] || [ ! -s "$LOH_CALLS_FILE" ] || [ ! -s "$LOH_CONF_FILE" ]; then
  echo "[ERROR] 06_cn_summary AxiomGT1 files are incomplete."
  echo "[ERROR] Required:"
  echo "  $SUMMARY_FILE"
  echo "  $REPORT_FILE"
  echo "  $LOH_CALLS_FILE"
  echo "  $LOH_CONF_FILE"
  exit 1
fi

CALLS_N=$(awk 'BEGIN{n=0} $1 !~ /^#/ && NR>1 {n++} END{print n}' "$LOH_CALLS_FILE")
CONF_N=$(awk 'BEGIN{n=0} $1 !~ /^#/ && NR>1 {n++} END{print n}' "$LOH_CONF_FILE")

echo "[INFO] AxAS-equivalent AxiomGT1 source forced = $AXIOMGT1_SOURCE"
echo "[INFO] SUMMARY_FILE  = $SUMMARY_FILE"
echo "[INFO] REPORT_FILE   = $REPORT_FILE"
echo "[INFO] LOH_CALLS_FILE= $LOH_CALLS_FILE"
echo "[INFO] LOH_CONF_FILE = $LOH_CONF_FILE"
echo "[INFO] calls probe rows       = $CALLS_N"
echo "[INFO] confidences probe rows = $CONF_N"

if [ "$CALLS_N" -lt 800000 ] || [ "$CONF_N" -lt 800000 ]; then
  echo "[ERROR] 06_cn_summary calls/confidences are not full AxAS-equivalent outputs."
  echo "[ERROR] Check 06_cn_summarization.sh and CN_XML."
  exit 1
fi



# [FIX] Rebuild HMM input symlinks from 06_cn_summary after forcing AxAS-equivalent inputs
echo "[INFO] Rebuilding HMM input symlinks from 06_cn_summary"

mkdir -p "$HMM_INPUT_DIR"

rm -f "$HMM_INPUT_DIR/AxiomGT1.calls.txt"
rm -f "$HMM_INPUT_DIR/AxiomGT1.confidences.txt"
rm -f "$HMM_INPUT_DIR/AxiomGT1.report.txt"
rm -f "$HMM_INPUT_DIR/AxiomGT1.summary.a5"

ln -sfn "$LOH_CALLS_FILE" "$HMM_INPUT_DIR/AxiomGT1.calls.txt"
ln -sfn "$LOH_CONF_FILE" "$HMM_INPUT_DIR/AxiomGT1.confidences.txt"
ln -sfn "$REPORT_FILE" "$HMM_INPUT_DIR/AxiomGT1.report.txt"
ln -sfn "$SUMMARY_FILE" "$HMM_INPUT_DIR/AxiomGT1.summary.a5"

echo "[CHECK] HMM input symlink"
ls -lh "$HMM_INPUT_DIR"

# ------------------------------------------------------------
# 5. Library / Copynumber.APT2Input 준비
# ------------------------------------------------------------

# HMM apt2 XML 찾기
LIB_HMM_XML=""

FORCED_HMM_APT2_XML="$PROJECT_DIR/Axiom_PangenomiX.r1/Axiom_PangenomiX.r1.apt-copynumber-axiom-hmm.AxiomHMM.apt2.xml"

if [ -f "$FORCED_HMM_APT2_XML" ]; then
  LIB_HMM_XML="$FORCED_HMM_APT2_XML"
else
  LIB_HMM_XML="$(
    find "$PROJECT_DIR/Axiom_PangenomiX.r1" \
         "$TEMPLATE_FILES_DIR" \
         "$LIB_DIR" \
         -type f \
         \( -iname "*AxiomHMM*.apt2.xml" \
            -o -iname "*apt-copynumber-axiom-hmm*.apt2.xml" \
            -o -iname "*hmm*.apt2.xml" \
            -o -iname "*hmm*.xml" \) \
         2>/dev/null | sort | head -1 || true
  )"
fi

if [ -z "$LIB_HMM_XML" ] || [ ! -f "$LIB_HMM_XML" ]; then
  echo "[ERROR] HMM apt2 xml을 찾지 못했습니다."
  echo "[ERROR] find target: Axiom_PangenomiX.r1.apt-copynumber-axiom-hmm.AxiomHMM.apt2.xml"
  echo "[ERROR] available xml candidates:"
  find "$PROJECT_DIR/Axiom_PangenomiX.r1" \
       "$TEMPLATE_FILES_DIR" \
       "$LIB_DIR" \
       -type f \( -iname "*.xml" -o -iname "*.apt2.xml" \) 2>/dev/null | head -50
  exit 1
fi

LIB_DIR="$(dirname "$LIB_HMM_XML")"

echo "[INFO] LIB_HMM_XML = $LIB_HMM_XML"
echo "[INFO] LIB_DIR     = $LIB_DIR"

CN_MODELS="$(find "$LIB_DIR" -maxdepth 1 -type f -name "Axiom_PangenomiX.r1.cn_models" | sort | head -1 || true)"
HMM_REGIONS="$(find "$LIB_DIR" -maxdepth 1 -type f -name "Axiom_PangenomiX.r1.hmm_regions.txt" | sort | head -1 || true)"
X_PROBES="$(find "$LIB_DIR" -maxdepth 1 -type f -name "Axiom_PangenomiX.r1.chrXprobes" | sort | head -1 || true)"
Y_PROBES="$(find "$LIB_DIR" -maxdepth 1 -type f -name "Axiom_PangenomiX.r1.chrYprobes" | sort | head -1 || true)"

for f in "$CN_MODELS" "$HMM_REGIONS" "$X_PROBES" "$Y_PROBES"; do
  if [ -z "$f" ] || [ ! -f "$f" ]; then
    echo "[ERROR] Library 필수 파일을 찾지 못했습니다."
    echo "[ERROR] LIB_DIR = $LIB_DIR"
    ls -lh "$LIB_DIR" | head -50
    exit 1
  fi
done

APT2_TEMPLATE="$(find "$TEMPLATE_FILES_DIR" -type f -path "*/Temp/Copynumber.APT2Input" | sort | head -1 || true)"

if [ -z "$APT2_TEMPLATE" ] || [ ! -f "$APT2_TEMPLATE" ]; then
  echo "[ERROR] template Copynumber.APT2Input을 찾지 못했습니다."
  exit 1
fi

APT2INPUT="$TEMP_DIR/Copynumber.APT2Input"
cp -f "$APT2_TEMPLATE" "$APT2INPUT"

echo ""
echo "[INFO] LIB_DIR       = $LIB_DIR"
echo "[INFO] LIB_HMM_XML   = $LIB_HMM_XML"
echo "[INFO] CN_MODELS     = $CN_MODELS"
echo "[INFO] HMM_REGIONS   = $HMM_REGIONS"
echo "[INFO] X_PROBES      = $X_PROBES"
echo "[INFO] Y_PROBES      = $Y_PROBES"
echo "[INFO] APT2INPUT     = $APT2INPUT"

# ------------------------------------------------------------
# 6. Copynumber.APT2Input 경로 보정
# ------------------------------------------------------------

python3 - "$APT2INPUT" "$CN_OUT" "$LIB_HMM_XML" "$CN_MODELS" "$HMM_REGIONS" "$LIB_DIR" "$SUMMARY_FILE" "$REPORT_FILE" "$LOH_CALLS_FILE" "$LOH_CONF_FILE" "$X_PROBES" "$Y_PROBES" <<'PY'
import sys
import re

apt2input = sys.argv[1]
cn_out = sys.argv[2]
lib_hmm_xml = sys.argv[3]
cn_models = sys.argv[4]
hmm_regions = sys.argv[5]
lib_dir = sys.argv[6]
summary_file = sys.argv[7]
report_file = sys.argv[8]
calls_file = sys.argv[9]
conf_file = sys.argv[10]
x_probes = sys.argv[11]
y_probes = sys.argv[12]

with open(apt2input, "r", errors="replace") as f:
    text = f.read()

def set_param(text, name, value):
    patterns = [
        r'(<Parameter\s+name="' + re.escape(name) + r'"\s+currentValue=")[^"]*("\s*/>)',
        r'(<Parameter\s+name="' + re.escape(name) + r'"\s+value=")[^"]*("\s*/>)',
    ]

    for pattern in patterns:
        if re.search(pattern, text):
            return re.sub(pattern, r'\g<1>' + value + r'\g<2>', text, count=1)

    # 없으면 추가하지 않고 에러. template 구조가 바뀐 것.
    raise SystemExit("[ERROR] Copynumber.APT2Input parameter not found: {}".format(name))

params = {
    "out-dir": cn_out,
    "arg-file": lib_hmm_xml,
    "reference-file": cn_models,
    "regions-file": hmm_regions,
    "analysis-files-path": lib_dir,
    "summary-file": summary_file,
    "report-file": report_file,
    "loh-calls-file": calls_file,
    "loh-confidences-file": conf_file,
}

for name, value in params.items():
    text = set_param(text, name, value)

with open(apt2input, "w") as f:
    f.write(text)

print("[OK] Copynumber.APT2Input 보정 완료")
for name in sorted(params):
    print("[OK] {} = {}".format(name, params[name]))
PY

# ------------------------------------------------------------
# 7. Discovery HMM 실행
# ------------------------------------------------------------

rm -rf "$CN_OUT"
mkdir -p "$CN_OUT"

LOG_FILE="$LOG_DIR/07_CopynumberAPT2.log"

echo ""
echo "[COMMAND]"

# [FIX] AxAS APT2 templates can retain Windows library paths.
# Convert them to Linux library paths before running apt-copynumber-axiom-hmm.
echo "[INFO] Sanitizing Windows AxAS library paths in CopyNumber.APT2Input"

python3 - "$APT2INPUT" "$LIB_DIR" <<'PY2'
from pathlib import Path
import sys
import re

apt2input = Path(sys.argv[1])
lib_dir = sys.argv[2].rstrip("/")

text = apt2input.read_text(errors="replace")

# Convert paths like:
# C:\Users\Public\Documents\AxiomAnalysisSuite\Library\Axiom_PangenomiX.r1\Axiom_PangenomiX.r1.chrYprobes
# to:
# /BiO/Pangenomics_test_260601/Axiom_PangenomiX.r1/Axiom_PangenomiX.r1.chrYprobes
patterns = [
    r"C:\\Users\\Public\\Documents\\AxiomAnalysisSuite\\Library\\Axiom_PangenomiX\.r1\\([^\"'<>\s]+)",
    r"C:/Users/Public/Documents/AxiomAnalysisSuite/Library/Axiom_PangenomiX\.r1/([^\"'<>\s]+)",
]

for pat in patterns:
    text = re.sub(
        pat,
        lambda m: lib_dir + "/" + m.group(1).replace("\\", "/"),
        text
    )

# Extra direct safety replacements
text = text.replace(
    r"C:\Users\Public\Documents\AxiomAnalysisSuite\Library\Axiom_PangenomiX.r1\Axiom_PangenomiX.r1.chrXprobes",
    lib_dir + "/Axiom_PangenomiX.r1.chrXprobes"
)
text = text.replace(
    r"C:\Users\Public\Documents\AxiomAnalysisSuite\Library\Axiom_PangenomiX.r1\Axiom_PangenomiX.r1.chrYprobes",
    lib_dir + "/Axiom_PangenomiX.r1.chrYprobes"
)

apt2input.write_text(text)

print("[INFO] CopyNumber.APT2Input path sanitization complete")
PY2

echo "[CHECK] Remaining Windows paths in CopyNumber.APT2Input"
grep -nE "C:\\\\Users|C:/Users" "$APT2INPUT" || true


echo "$APT_HMM --log-file $LOG_FILE --arg-file $APT2INPUT"

"$APT_HMM" \
  --log-file "$LOG_FILE" \
  --arg-file "$APT2INPUT"

# ------------------------------------------------------------
# 8. 결과 검증
# ------------------------------------------------------------

CNV_A5="$(find "$CN_OUT" -maxdepth 2 -type f -name "*.cnv.a5" | sort | head -1 || true)"
HMM_REPORT_OUT="$(find "$CN_OUT" -maxdepth 2 -type f \( -name "AxiomHMM.report.txt" -o -name "*.report.txt" -o -name "AxiomHMM.report" \) | sort | head -1 || true)"

if [ -z "$CNV_A5" ] || [ ! -f "$CNV_A5" ]; then
  echo "[ERROR] HMM 결과 AxiomHMM.cnv.a5가 생성되지 않았습니다."
  find "$CN_OUT" -maxdepth 3 -type f | sort || true
  exit 1
fi

if [ "$(basename "$CNV_A5")" != "AxiomHMM.cnv.a5" ]; then
  cp -f "$CNV_A5" "$CN_OUT/AxiomHMM.cnv.a5"
fi

if [ -n "$HMM_REPORT_OUT" ] && [ -f "$HMM_REPORT_OUT" ] && [ "$(basename "$HMM_REPORT_OUT")" != "AxiomHMM.report.txt" ]; then
  cp -f "$HMM_REPORT_OUT" "$CN_OUT/AxiomHMM.report.txt"
fi

echo ""

# [FIX] Persist CopyNumber.APT2Input for AxAS batch packaging
mkdir -p "$OUT/Temp"

if [ -s "$APT2INPUT" ]; then
  cp -f "$APT2INPUT" "$OUT/Temp/CopyNumber.APT2Input"
  echo "[INFO] Saved CopyNumber.APT2Input for AxAS batch:"
  echo "  $OUT/Temp/CopyNumber.APT2Input"
else
  echo "[ERROR] CopyNumber.APT2Input was not created: $APT2INPUT"
  exit 1
fi


echo "[CHECK] HMM 결과"
ls -lh "$CN_OUT/AxiomHMM.cnv.a5" 2>/dev/null || ls -lh "$CNV_A5"
ls -lh "$CN_OUT/AxiomHMM.report.txt" 2>/dev/null || true

echo ""
echo "[CHECK] 사용된 AxiomGT1 입력"
ls -lh "$HMM_INPUT_DIR"

echo ""
echo "[DONE] 07 Discovery HMM 완료"
