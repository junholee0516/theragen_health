#!/usr/bin/env bash
set -Eeuo pipefail

if [ $# -lt 2 ]; then
  echo "[사용법]"
  echo "bash scripts/cnv_pipeline/run_master.sh <CEL_DIR> <RUN_NAME> [TEMPLATE_FILES_DIR]"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE="$(cd "$SCRIPT_DIR/../.." && pwd)"

CEL_DIR="$1"
RUN_NAME="$2"
TEMPLATE_FILES_DIR="${3:-${BASE}/input/axas_template_files}"

OUT="${BASE}/output/cnv_runs/${RUN_NAME}"
LOG_DIR="${OUT}/logs"
CHECKPOINT_DIR="${OUT}/checkpoints"
TIMES_FILE="${OUT}/pipeline_step_times.tsv"

mkdir -p "$OUT" "$LOG_DIR" "$CHECKPOINT_DIR"

# [LOG] Save full run_master console output automatically
MASTER_LOG="$OUT/run_master.console.log"
echo "[LOG] run_master console log = $MASTER_LOG"
exec > >(tee "$MASTER_LOG") 2>&1
echo "[LOG] Started at $(date '+%Y-%m-%d %H:%M:%S')"
echo "[LOG] Command: $0 $*"
echo

find_one_file() {
  local root="$1"
  shift

  local pattern
  local hit

  if [ ! -d "$root" ]; then
    return 0
  fi

  for pattern in "$@"; do
    hit="$(find "$root" -type f -iname "$pattern" 2>/dev/null | sort | head -1 || true)"
    if [ -n "$hit" ]; then
      echo "$hit"
      return 0
    fi
  done
}

find_one_dir() {
  local root="$1"
  shift

  local pattern
  local hit

  if [ ! -d "$root" ]; then
    return 0
  fi

  for pattern in "$@"; do
    hit="$(find "$root" -type d -iname "$pattern" 2>/dev/null | sort | head -1 || true)"
    if [ -n "$hit" ]; then
      echo "$hit"
      return 0
    fi
  done
}

APT_BIN="${APT_BIN:-${BASE}/bin}"

APT_DISHQC="${APT_DISHQC:-}"
APT_GT="${APT_GT:-}"
APT_HMM="${APT_HMM:-}"
APT_FORMAT="${APT_FORMAT:-}"

if [ -z "$APT_DISHQC" ] || [ ! -f "$APT_DISHQC" ]; then
  APT_DISHQC="$(command -v apt-geno-qc-axiom || true)"
fi
if [ -z "$APT_DISHQC" ] || [ ! -f "$APT_DISHQC" ]; then
  APT_DISHQC="$(find_one_file "$BASE" "apt-geno-qc-axiom" "apt-geno-qc-axiom*")"
fi

if [ -z "$APT_GT" ] || [ ! -f "$APT_GT" ]; then
  APT_GT="$(command -v apt-genotype-axiom || true)"
fi
if [ -z "$APT_GT" ] || [ ! -f "$APT_GT" ]; then
  APT_GT="$(find_one_file "$BASE" "apt-genotype-axiom" "apt-genotype-axiom*")"
fi

if [ -z "$APT_HMM" ] || [ ! -f "$APT_HMM" ]; then
  APT_HMM="$(command -v apt-copynumber-axiom-hmm || true)"
fi
if [ -z "$APT_HMM" ] || [ ! -f "$APT_HMM" ]; then
  APT_HMM="$(find_one_file "$BASE" "apt-copynumber-axiom-hmm" "apt-copynumber-axiom-hmm*")"
fi

if [ -z "$APT_FORMAT" ] || [ ! -f "$APT_FORMAT" ]; then
  APT_FORMAT="$(command -v apt-format-result || true)"
fi
if [ -z "$APT_FORMAT" ] || [ ! -f "$APT_FORMAT" ]; then
  APT_FORMAT="$(find_one_file "$BASE" "apt-format-result" "apt-format-result*")"
fi

LIB_DIR="${LIB_DIR:-}"
if [ -z "$LIB_DIR" ] || [ ! -d "$LIB_DIR" ]; then
  LIB_DIR="$(find_one_dir "$BASE" "Axiom_PangenomiX.r1" "Axiom_Pangenomix.r1")"
fi

if [ -z "$LIB_DIR" ] || [ ! -d "$LIB_DIR" ]; then
  echo "[ERROR] Axiom library 폴더를 찾지 못했습니다."
  echo "[CHECK] BASE = $BASE"
  find "$BASE" -maxdepth 3 -type d | grep -i "Axiom_Pangenomi" || true
  exit 1
fi

DISHQC_XML="${DISHQC_XML:-}"
CALLRATE_XML="${CALLRATE_XML:-}"
CN_XML="${CN_XML:-}"
HMM_ARG_FILE="${HMM_ARG_FILE:-}"
CN_MODELS="${CN_MODELS:-}"
HMM_REGIONS="${HMM_REGIONS:-}"
Y_PROBES_FILE="${Y_PROBES_FILE:-}"

if [ -z "$DISHQC_XML" ] || [ ! -f "$DISHQC_XML" ]; then
  DISHQC_XML="$(find_one_file "$LIB_DIR" "*apt-geno-qc-axiom*.xml" "*apt-geno-qc*.xml" "*AxiomQC*.xml")"
fi

if [ -z "$CALLRATE_XML" ] || [ ! -f "$CALLRATE_XML" ]; then
  CALLRATE_XML="$(find_one_file "$LIB_DIR" "*apt-genotype-axiom*AxiomGT1*.xml" "*AxiomGT1*.apt2.xml")"
fi

if [ -z "$CN_XML" ] || [ ! -f "$CN_XML" ]; then
  CN_XML="$(find_one_file "$LIB_DIR" "*apt-genotype-axiom*AxiomCN_GT1*.xml" "*AxiomCN_GT1*.apt2.xml")"
fi

if [ -z "$HMM_ARG_FILE" ] || [ ! -f "$HMM_ARG_FILE" ]; then
  HMM_ARG_FILE="$(find_one_file "$LIB_DIR" "*apt-copynumber-axiom-hmm*AxiomHMM*.xml" "*AxiomHMM*.apt2.xml")"
fi

if [ -z "$CN_MODELS" ] || [ ! -f "$CN_MODELS" ]; then
  CN_MODELS="$(find_one_file "$LIB_DIR" "*.cn_models" "*cn_models*")"
fi

if [ -z "$HMM_REGIONS" ] || [ ! -f "$HMM_REGIONS" ]; then
  HMM_REGIONS="$(find_one_file "$LIB_DIR" "*.hmm_regions.txt" "*.hmm_regions" "*hmm_regions*")"
fi

if [ -z "$Y_PROBES_FILE" ] || [ ! -f "$Y_PROBES_FILE" ]; then
  Y_PROBES_FILE="$(find_one_file "$LIB_DIR" "*.chrYprobes" "*chrYprobes*")"
fi

# ============================================================
# output 폴더 번호 = pipeline step 번호
# ============================================================

CEL_LIST="${OUT}/01_input/cel_list.txt"

DISHQC_DIR="${OUT}/02_dishqc"
DISH_PASS_LIST="${OUT}/03_dishqc_pass/cel_list_dishqc_pass.txt"
DQC_PASS_LIST="$DISH_PASS_LIST"

CALLRATE_DIR="${OUT}/04_callrate"
CALLRATE_PASS_LIST="${OUT}/05_qc_pass/cel_list_qc_pass.txt"
QC_PASS_LIST="$CALLRATE_PASS_LIST"

SUM_DIR="${OUT}/06_cn_summary"
HMM_DIR="${OUT}/07_discovery_hmm"
FINAL_DIR="${OUT}/08_final_tables"

AXAS_DIR="${OUT}/AxAS_Copy_Number_Discovery_batch_${RUN_NAME}"

DQC_THRESHOLD="${DQC_THRESHOLD:-0.82}"
CALLRATE_THRESHOLD="${CALLRATE_THRESHOLD:-97}"

MAPD_MAX="${MAPD_MAX:-0.35}"
MAPDC_MAX="${MAPDC_MAX:-0.35}"
WAVINESS_SD_MAX="${WAVINESS_SD_MAX:-0.1}"
WAVINESS_SDC_MAX="${WAVINESS_SDC_MAX:-0.1}"

CEL_WIN_PREFIX="${CEL_WIN_PREFIX:-C:\\Users\\Public\\Documents\\AxiomAnalysisSuite\\cel\\}"

CONFIG="${OUT}/run_config.sh"

emit() {
  local key="$1"
  local value="$2"
  printf '%s=%q\n' "$key" "$value"
}

{
  emit BASE "$BASE"
  emit SCRIPT_DIR "$SCRIPT_DIR"
  emit CEL_DIR "$CEL_DIR"
  emit RUN_NAME "$RUN_NAME"
  emit OUT "$OUT"
  emit LOG_DIR "$LOG_DIR"
  emit CHECKPOINT_DIR "$CHECKPOINT_DIR"
  emit TIMES_FILE "$TIMES_FILE"
  emit TEMPLATE_FILES_DIR "$TEMPLATE_FILES_DIR"

  emit LIB_DIR "$LIB_DIR"

  emit APT_DISHQC "$APT_DISHQC"
  emit APT_GT "$APT_GT"
  emit APT_HMM "$APT_HMM"
  emit APT_FORMAT "$APT_FORMAT"

  emit DISHQC_XML "$DISHQC_XML"
  emit CALLRATE_XML "$CALLRATE_XML"
  emit CN_XML "$CN_XML"
  emit HMM_ARG_FILE "$HMM_ARG_FILE"
  emit CN_MODELS "$CN_MODELS"
  emit HMM_REGIONS "$HMM_REGIONS"
  emit Y_PROBES_FILE "$Y_PROBES_FILE"

  emit CEL_LIST "$CEL_LIST"

  emit DISHQC_DIR "$DISHQC_DIR"
  emit DISH_PASS_LIST "$DISH_PASS_LIST"
  emit DQC_PASS_LIST "$DQC_PASS_LIST"

  emit CALLRATE_DIR "$CALLRATE_DIR"
  emit CALLRATE_PASS_LIST "$CALLRATE_PASS_LIST"
  emit QC_PASS_LIST "$QC_PASS_LIST"

  emit SUM_DIR "$SUM_DIR"
  emit HMM_DIR "$HMM_DIR"
  emit FINAL_DIR "$FINAL_DIR"
  emit AXAS_DIR "$AXAS_DIR"

  emit DQC_THRESHOLD "$DQC_THRESHOLD"
  emit CALLRATE_THRESHOLD "$CALLRATE_THRESHOLD"

  emit MAPD_MAX "$MAPD_MAX"
  emit MAPDC_MAX "$MAPDC_MAX"
  emit WAVINESS_SD_MAX "$WAVINESS_SD_MAX"
  emit WAVINESS_SDC_MAX "$WAVINESS_SDC_MAX"

  emit CEL_WIN_PREFIX "$CEL_WIN_PREFIX"
} > "$CONFIG"

echo "============================================================"
echo "CNV pipeline 시작"
echo "============================================================"
echo "[BASE]               $BASE"
echo "[SCRIPT_DIR]         $SCRIPT_DIR"
echo "[RUN_NAME]           $RUN_NAME"
echo "[CEL_DIR]            $CEL_DIR"
echo "[OUT]                $OUT"
echo "[CONFIG]             $CONFIG"
echo "[TIMES_FILE]         $TIMES_FILE"
echo "[TEMPLATE_FILES_DIR] $TEMPLATE_FILES_DIR"
echo "[LIB_DIR]            $LIB_DIR"
echo "[DISHQC_XML]         $DISHQC_XML"
echo "[CALLRATE_XML]       $CALLRATE_XML"
echo "[CN_XML]             $CN_XML"
echo "[HMM_ARG_FILE]       $HMM_ARG_FILE"
echo "[AXAS_DIR]           $AXAS_DIR"
echo "============================================================"

fmt_seconds() {
  local total="$1"
  local h=$((total / 3600))
  local m=$(((total % 3600) / 60))
  local sec=$((total % 60))
  printf "%02d:%02d:%02d" "$h" "$m" "$sec"
}

init_times_file() {
  mkdir -p "$(dirname "$TIMES_FILE")"

  if [ ! -f "$TIMES_FILE" ]; then
    printf "step\tscript\tlabel\tstatus\tstart_time\tend_time\telapsed_seconds\telapsed_hms\tlog_file\n" > "$TIMES_FILE"
  fi
}

append_time_record() {
  local step="$1"
  local script="$2"
  local label="$3"
  local status="$4"
  local start_time="$5"
  local end_time="$6"
  local elapsed="$7"
  local elapsed_hms="$8"
  local log="$9"

  init_times_file

  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "$step" "$script" "$label" "$status" "$start_time" "$end_time" "$elapsed" "$elapsed_hms" "$log" \
    >> "$TIMES_FILE"
}

run_step() {
  local step="$1"
  local script="$2"
  local label="$3"

  # step 번호 변경 후 기존 08_SUCCESS/09_SUCCESS와 충돌 방지용으로 script명 포함
  local script_key
  script_key="${script%.sh}"

  local checkpoint="${CHECKPOINT_DIR}/${step}_${script_key}_SUCCESS"
  local log="${LOG_DIR}/${step}_${script}.log"

  echo ""
  echo "============================================================"
  echo "[${step}] ${label}"
  echo "============================================================"

  if [ -f "$checkpoint" ]; then
    local now_time
    now_time=$(date '+%Y-%m-%d %H:%M:%S')

    echo "[SKIP] 이미 완료됨: $checkpoint"
    echo "[TIME] 이미 완료된 step이라 실행 시간 계산 없음"

    append_time_record "$step" "$script" "$label" "SKIP" "$now_time" "$now_time" "0" "00:00:00" "$log"
    return 0
  fi

  local start_epoch
  local end_epoch
  local elapsed
  local elapsed_hms
  local start_time
  local end_time
  local status

  start_epoch=$(date +%s)
  start_time=$(date '+%Y-%m-%d %H:%M:%S')

  echo "[START] $label"
  echo "[START TIME] $start_time"
  echo "[LOG] $log"

  set +e
  bash "${SCRIPT_DIR}/${script}" "$CONFIG" > "$log" 2>&1
  status=$?
  set -e

  end_epoch=$(date +%s)
  end_time=$(date '+%Y-%m-%d %H:%M:%S')
  elapsed=$((end_epoch - start_epoch))
  elapsed_hms=$(fmt_seconds "$elapsed")

  if [ "$status" -ne 0 ]; then
    echo "[FAIL] $label"
    echo "[FAIL STEP] $step / $script"
    echo "[START TIME] $start_time"
    echo "[END TIME] $end_time"
    echo "[TIME BEFORE FAIL] ${elapsed_hms} (${elapsed} sec)"
    echo "[LOG] $log"

    append_time_record "$step" "$script" "$label" "FAIL" "$start_time" "$end_time" "$elapsed" "$elapsed_hms" "$log"

    echo ""
    echo "마지막 로그 120줄:"
    tail -120 "$log" || true
    exit "$status"
  fi

  touch "$checkpoint"

  echo "[DONE] $label"
  echo "[END TIME] $end_time"
  echo "[TIME] ${elapsed_hms} (${elapsed} sec)"
  echo "[LOG] $log"

  append_time_record "$step" "$script" "$label" "DONE" "$start_time" "$end_time" "$elapsed" "$elapsed_hms" "$log"
}

init_times_file

run_step "01" "01_make_cel_list.sh"       "CEL list 생성"
run_step "02" "02_dishqc.sh"              "DishQC 실행"
run_step "03" "03_filter_dishqc.sh"       "DishQC PASS list 생성"
run_step "04" "04_callrate.sh"            "QC Call Rate 실행"
run_step "05" "05_filter_callrate.sh"     "QC PASS list 생성"
run_step "06" "06_cn_summarization.sh"    "CN probeset summarization 실행"
run_step "07" "07_discovery_hmm.sh"       "Discovery HMM 실행"
run_step "08" "08_make_final_tables.sh"   "최종 CNV 위치표 및 샘플별 개수표 생성"
# 09는 AxAS batch를 현재 CEL_LIST 기준으로 다시 포장해야 하므로 항상 재실행
# 09/99는 AxAS batch metadata를 현재 CEL 기준으로 다시 만들어야 하므로 항상 재실행
# 09는 AxAS batch를 현재 CEL 기준으로 다시 만들어야 하므로 항상 재실행
rm -f "${CHECKPOINT_DIR}/09_09_package_axas_batch_SUCCESS"
run_step "09" "09_package_axas_batch.sh"  "AxAS Copy Number Discovery batch folder 생성"
rm -f "${CHECKPOINT_DIR}/99_99_apply_mapd_configuration_from_template_SUCCESS"
run_step "99" "99_apply_mapd_configuration_from_template.sh" "AxAS 설정 파일 적용"

echo ""
echo "============================================================"
echo "[DONE] 전체 CNV pipeline 완료"
echo "============================================================"
echo "[OUT]        $OUT"
echo "[AXAS_DIR]   $AXAS_DIR"
echo "[TIMES_FILE] $TIMES_FILE"
