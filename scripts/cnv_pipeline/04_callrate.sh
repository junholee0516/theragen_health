#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG="${1:?run_config.sh 필요}"
source "$CONFIG"

echo "============================================================"
echo "[04] QC Call Rate / Genotyping 실행 - AxAS GenoTyping.APT2Input replay"
echo "============================================================"

GT_TEMPLATE="$(find "$TEMPLATE_FILES_DIR/Temp" -maxdepth 1 -type f \
  \( -iname "GenoTyping.APT2Input" -o -iname "Genotyping.APT2Input" -o -iname "*genotyping*.APT2Input" \) \
  | sort | head -1 || true)"

TEMP_DIR="${OUT}/Temp"
GT_INPUT="${TEMP_DIR}/GenoTyping.APT2Input"
APT_LOG="${LOG_DIR}/04_GenotypingAPT2.log"

mkdir -p "$CALLRATE_DIR" "$SUM_DIR" "$TEMP_DIR" "$LOG_DIR"

REPORT_FILE="${CALLRATE_DIR}/AxiomGT1.report.txt"
CALLS_FILE="${CALLRATE_DIR}/AxiomGT1.calls.txt"
CONF_FILE="${CALLRATE_DIR}/AxiomGT1.confidences.txt"
SUMMARY_CALLRATE="${CALLRATE_DIR}/AxiomGT1.summary.a5"
SUMMARY_FILE="${SUM_DIR}/AxiomGT1.summary.a5"

echo "[INFO] APT_GT       = $APT_GT"
echo "[INFO] GT_TEMPLATE  = $GT_TEMPLATE"
echo "[INFO] GT_INPUT     = $GT_INPUT"
echo "[INFO] CEL_LIST     = $CEL_LIST"
echo "[INFO] CALLRATE_DIR = $CALLRATE_DIR"
echo "[INFO] SUM_DIR      = $SUM_DIR"
echo ""

for pair in \
  "APT_GT:$APT_GT" \
  "GT_TEMPLATE:$GT_TEMPLATE" \
  "CALLRATE_XML:$CALLRATE_XML" \
  "LIB_DIR:$LIB_DIR" \
  "CEL_LIST:$CEL_LIST"
do
  label="${pair%%:*}"
  path="${pair#*:}"

  if [ -z "$path" ] || [ ! -e "$path" ]; then
    echo "[ERROR] $label 파일/폴더가 없습니다."
    echo "[ERROR] path = $path"
    exit 1
  fi
done

rm -rf "$CALLRATE_DIR"
mkdir -p "$CALLRATE_DIR"

python3 - "$GT_TEMPLATE" "$GT_INPUT" \
  "$APT_GT" "$CALLRATE_DIR" "$CALLRATE_XML" "$LIB_DIR" "$CEL_LIST" \
  "$REPORT_FILE" "$CALLS_FILE" "$CONF_FILE" "$SUMMARY_CALLRATE" <<'PY'
import sys
import os
import xml.etree.ElementTree as ET

template_path = sys.argv[1]
out_path = sys.argv[2]

apt_gt = sys.argv[3]
out_dir = sys.argv[4]
arg_file = sys.argv[5]
lib_dir = sys.argv[6]
cel_list = sys.argv[7]
report_file = sys.argv[8]
calls_file = sys.argv[9]
conf_file = sys.argv[10]
summary_file = sys.argv[11]

core_map = {
    "out-dir": out_dir,
    "arg-file": arg_file,
    "analysis-files-path": lib_dir,
    "cel-files": cel_list,
    "temp-dir": os.path.join(out_dir, "APTTemp"),
}

optional_map = {
    "report-file": report_file,
    "calls-file": calls_file,
    "confidences-file": conf_file,
    "summary-file": summary_file,
}

tree = ET.parse(template_path)
root = tree.getroot()

for elem in root.iter():
    if "executableName" in elem.attrib:
        elem.set("executableName", apt_gt)

params_node = None
found_core = set()

for elem in root.iter():
    if elem.tag.endswith("Parameters"):
        params_node = elem

    if not elem.tag.endswith("Parameter"):
        continue

    name = elem.attrib.get("name")
    val = elem.attrib.get("currentValue", "")

    if name in core_map:
        elem.set("currentValue", core_map[name])
        found_core.add(name)
        continue

    if name in optional_map:
        elem.set("currentValue", optional_map[name])
        continue

    # Windows Library 경로가 남아 있으면 Linux library 경로로 치환
    if "AxiomAnalysisSuite\\Library" in val or "AxiomAnalysisSuite/Library" in val:
        base = val.replace("\\", "/").split("/")[-1]
        elem.set("currentValue", os.path.join(lib_dir, base))

    # Windows Output 경로가 남아 있으면 현재 CALLRATE_DIR 기준으로 치환
    if "AxiomAnalysisSuite\\Output" in val or "AxiomAnalysisSuite/Output" in val:
        base = val.replace("\\", "/").split("/")[-1]
        if base.lower() == "genotyping_cel_files.txt":
            elem.set("currentValue", cel_list)
        elif base:
            elem.set("currentValue", os.path.join(out_dir, base))
        else:
            elem.set("currentValue", out_dir)

if params_node is None:
    raise SystemExit("[ERROR] Parameters node를 찾지 못했습니다.")

# 핵심 parameter가 template에 없으면 추가
for name, value in core_map.items():
    if name not in found_core:
        child = ET.Element("Parameter")
        child.set("name", name)
        child.set("currentValue", value)
        params_node.append(child)

tree.write(out_path, encoding="utf-8", xml_declaration=True)

with open(out_path, "r") as f:
    text = f.read()

bad = False
for key in ["C:", "Users\\Public", "AxiomAnalysisSuite\\Library", "AxiomAnalysisSuite\\Output"]:
    if key in text:
        bad = True

if bad:
    print("[ERROR] GenoTyping.APT2Input에 Windows 경로가 남아 있습니다.")
    for line in text.splitlines():
        if "C:" in line or "Users\\Public" in line or "AxiomAnalysisSuite\\Library" in line or "AxiomAnalysisSuite\\Output" in line:
            print(line)
    raise SystemExit(1)

print("[OK] GenoTyping.APT2Input 생성 완료")
print("[OK] Windows 경로 없음")
PY

echo ""
echo "[CHECK] GenoTyping.APT2Input 주요 경로"
grep -o 'name="[^"]*" currentValue="[^"]*"' "$GT_INPUT" \
  | grep -E 'out-dir|arg-file|analysis-files-path|cel-files|temp-dir|report-file|calls-file|confidences-file|summary-file' || true

echo ""
echo "[COMMAND]"
echo "$APT_GT --log-file $APT_LOG --arg-file $GT_INPUT"
echo ""

"$APT_GT" \
  --log-file "$APT_LOG" \
  --arg-file "$GT_INPUT"

safe_cp() {
  local src="$1"
  local dst="$2"

  if [ -z "$src" ] || [ ! -f "$src" ]; then
    return 0
  fi

  if [ -f "$dst" ] && [ "$(readlink -f "$src")" = "$(readlink -f "$dst")" ]; then
    return 0
  fi

  cp -a "$src" "$dst"
}

FOUND_REPORT="$(find "$CALLRATE_DIR" -maxdepth 2 -type f -iname "*AxiomGT1*report*.txt" | sort | head -1 || true)"
FOUND_CALLS="$(find "$CALLRATE_DIR" -maxdepth 2 -type f -iname "*AxiomGT1*calls*.txt" | sort | head -1 || true)"
FOUND_CONF="$(find "$CALLRATE_DIR" -maxdepth 2 -type f -iname "*AxiomGT1*confidences*.txt" | sort | head -1 || true)"
FOUND_SUMMARY="$(find "$CALLRATE_DIR" -maxdepth 2 -type f -iname "*AxiomGT1*summary*.a5" | sort | head -1 || true)"

safe_cp "$FOUND_REPORT" "$REPORT_FILE"
safe_cp "$FOUND_CALLS" "$CALLS_FILE"
safe_cp "$FOUND_CONF" "$CONF_FILE"
safe_cp "$FOUND_SUMMARY" "$SUMMARY_CALLRATE"

if [ ! -f "$REPORT_FILE" ] || [ ! -f "$CALLS_FILE" ] || [ ! -f "$CONF_FILE" ]; then
  echo "[ERROR] AxiomGT1 report/calls/confidences 중 일부가 생성되지 않았습니다."
  find "$CALLRATE_DIR" -maxdepth 3 -type f | sort
  exit 1
fi

if [ ! -f "$SUMMARY_CALLRATE" ]; then
  echo "[WARN] 04_callrate 단계에서는 AxiomGT1.summary.a5가 없어도 정상입니다."
  echo "[WARN] AxiomGT1.summary.a5는 06_cn_summarization 단계에서 CN_XML 기준으로 생성합니다."
else
  echo "[INFO] 04_callrate summary exists: $SUMMARY_CALLRATE"
fi

echo ""

# [FIX] Persist GenoTyping.APT2Input for AxAS batch packaging
mkdir -p "$OUT/Temp"

if [ -s "$GT_INPUT" ]; then
  DEST_GT_INPUT="$OUT/Temp/GenoTyping.APT2Input"

  if [ "$(readlink -f "$GT_INPUT")" = "$(readlink -f "$DEST_GT_INPUT" 2>/dev/null || echo "$DEST_GT_INPUT")" ]; then
    echo "[INFO] GenoTyping.APT2Input already saved: $DEST_GT_INPUT"
  else
    cp -f "$GT_INPUT" "$DEST_GT_INPUT"
  fi
  echo "[INFO] Saved GenoTyping.APT2Input for AxAS batch:"
  echo "  $OUT/Temp/GenoTyping.APT2Input"
else
  echo "[WARN] GenoTyping.APT2Input was not found at: $GT_INPUT"
fi


echo "[OK] AxiomGT1 파일 생성 완료"
ls -lh "$REPORT_FILE"
ls -lh "$CALLS_FILE"
ls -lh "$CONF_FILE"
ls -lh "$SUMMARY_CALLRATE" 2>/dev/null || echo "[INFO] 04 summary 없음; 06에서 생성 예정"

echo ""
echo "[DONE] QC Call Rate / Genotyping 완료"
