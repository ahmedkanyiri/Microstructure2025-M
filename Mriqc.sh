#!/bin/bash
# MRIQC Quality Control Pipeline Script
#
# Usage:
#   ./mriqc_steps.sh /path/to/raw /path/to/derivatives
#
# Example:
#   ./mriqc_steps.sh ~/path/to/raw ~/path/to/derivatives
#
# Outputs:
#   - Participant-level QC reports (HTML/JSON/TSV)
#   - Group-level summary reports
#   - qc_log.tsv for manual Pass/Fail notes
#
set -euo pipefail

# ==============================
# 0. Parse input arguments
# ==============================
if [ $# -lt 2 ]; then
  echo "Usage: $0 /path/to/raw /path/to/derivatives"
  exit 1
fi

RAW_DIR="$1"
DERIV_DIR="$2"
QC_DIR="$DERIV_DIR/QC"
WORK_DIR=~/mriqc_work

# ==============================
# 1. Helper functions
# ==============================

create_qc_dir() {
  echo ">>> Step 10.1: Creating MRIQC output folder..."
  mkdir -p "$QC_DIR"
  echo "Checkpoint: QC folder ready at $QC_DIR"
}

load_mriqc() {
  echo ">>> Step 10.2: Loading MRIQC module..."
  ml mriqc/24.0.2 || {
    echo "Error: MRIQC module not found. Start MRIQC from NeuroDesk Apps."
    exit 1
  }
  echo "Checkpoint: MRIQC loaded successfully."
}

run_mriqc_participant() {
  echo ">>> Step 10.3a: Running MRIQC (participant-level)..."
  rm -rf "$WORK_DIR" && mkdir -p "$WORK_DIR"

  mriqc "$RAW_DIR" "$QC_DIR" participant \
        --nprocs 1 --omp-nthreads 1 --no-sub \
        --work-dir "$WORK_DIR"

  echo "Checkpoint: Participant-level QC complete."
}


manual_qc_reminder() {
  echo ">>> Step 10.4: Manual visual QC required."
  echo "Open participant reports in a browser, e.g.:"
  echo "firefox $QC_DIR/sub-XXX_T1w.html"
  echo "firefox $QC_DIR/sub-XXX_dwi.html"
}

create_qc_log() {
  echo ">>> Step 10.5: Creating QC log..."
  QC_LOG="$QC_DIR/qc_log.tsv"
  if [ ! -f "$QC_LOG" ]; then
    echo -e "sub_ID\tT1w_QC\tDWI_QC\tstatus" > "$QC_LOG"
    echo "Checkpoint: Created $QC_LOG"
  else
    echo "QC log already exists at $QC_LOG. Update after inspection."
  fi
}

# ==============================
# 2. Main workflow
# ==============================
echo "===== MRIQC QC Pipeline Started ====="

create_qc_dir

if [[ "$GOOGLE_COLAB" == "True" ]]; then
    echo "Running in Google Colab"
else
    load_mriqc
fi

run_mriqc_participant
manual_qc_reminder
create_qc_log

echo "===== MRIQC QC Pipeline Finished ====="
