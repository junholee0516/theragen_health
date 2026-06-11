#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG="${1:?run_config.sh 필요}"
source "$CONFIG"

echo "============================================================"
echo "[02] DishQC 실행"
echo "============================================================"

mkdir -p "$DISHQC_DIR"

if [ ! -f "$APT_DISHQC" ]; then
  echo "[ERROR] APT_DISHQC 파일이 없습니다: $APT_DISHQC"
  exit 1
fi

if [ ! -f "$DISHQC_XML" ]; then
  echo "[ERROR] DISHQC_XML 파일이 없습니다: $DISHQC_XML"
  exit 1
fi

if [ ! -f "$CEL_LIST" ]; then
  echo "[ERROR] CEL_LIST 파일이 없습니다: $CEL_LIST"
  exit 1
fi

echo "[INFO] APT_DISHQC = $APT_DISHQC"
echo "[INFO] DISHQC_XML = $DISHQC_XML"
echo "[INFO] CEL_LIST   = $CEL_LIST"
echo "[INFO] OUT        = $DISHQC_DIR"

rm -rf "$DISHQC_DIR"
mkdir -p "$DISHQC_DIR"

"$APT_DISHQC" \
  --analysis-files-path "$LIB_DIR" \
  --arg-file "$DISHQC_XML" \
  --cel-files "$CEL_LIST" \
  --out-dir "$DISHQC_DIR"

echo "[OK] DishQC 완료"
find "$DISHQC_DIR" -maxdepth 2 -type f | sort
