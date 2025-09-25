#!/bin/bash

# Full pipeline:
#  - MRtrix: dwidenoise -> mrdegibbs -> dwigradcheck (AP and PA)
#  - TOPUP using AP+PA B0s (prefix topup_AP_PA_b0)
#  - create index_full.txt (AP then PA) for record
#  - run eddy_cpu on AP-only degibbs (use topup results), using AP-only index.txt
#  - final BET on eddy-corrected AP image
#
# Usage:
#   ./Preprocessing.sh /path/to/raw /path/to/derivatives

set -euo pipefail

# Load modules (adjust to your environment)
ml mrtrix3/3.0.4
ml fsl/6.0.7.16

raw_dir="$1"
deriv_dir="$2"

mkdir -p "$deriv_dir/MRtrix3"
mkdir -p "$deriv_dir/fsl"

# ---------- helper functions ----------
denoise_mrtrix() {
  in="$1"; out="$2"
  echo "    dwidenoise: $in -> $out"
  dwidenoise "$in" "$out"
}

degibbs_mrtrix() {
  in="$1"; out="$2"
  echo "    mrdegibbs: $in -> $out"
  mrdegibbs "$in" "$out"
}

gradcheck_mrtrix() {
  in="$1"; bvec="$2"; bval="$3"; outbase="$4"
  echo "    dwigradcheck: $in (bvec=$bvec, bval=$bval) -> ${outbase}.bvec/.bval"
  dwigradcheck "$in" -fslgrad "$bvec" "$bval" -export_grad_fsl "${outbase}.bvec" "${outbase}.bval"
}

run_topup() {
  degibbs_ap="$1"; degibbs_pa="$2"; subj_fsl_dir="$3"

  B0_AP="$subj_fsl_dir/b0_ap.nii.gz"
  B0_PA="$subj_fsl_dir/b0_pa.nii.gz"
  B0_MERGED="$subj_fsl_dir/b0_merged.nii.gz"
  ACQ="$subj_fsl_dir/acqparams.txt"
  TOPUP_PREFIX="$subj_fsl_dir/topup_AP_PA_b0"
  TOPUP_CORR_BASE="$subj_fsl_dir/topup_corrected_b0"

  echo "    extracting B0s"
  fslroi "$degibbs_ap" "$B0_AP" 0 1
  fslroi "$degibbs_pa" "$B0_PA" 0 1

  echo "    merging B0s"
  fslmerge -t "$B0_MERGED" "$B0_AP" "$B0_PA"

  printf "0 1 0 0.05\n0 -1 0 0.05\n" > "$ACQ"

  echo "    running topup -> prefix: $TOPUP_PREFIX"
  topup --imain="$B0_MERGED" --datain="$ACQ" --config=b02b0_1.cnf --out="$TOPUP_PREFIX" --iout="$TOPUP_CORR_BASE"

  echo "    BET on topup-corrected B0 to create mask"
  bet "${TOPUP_CORR_BASE}.nii.gz" "${subj_fsl_dir}/b0_brain" -m -f 0.3
}

run_eddy_cpu_ap_with_topup() {
  degibbs_ap="$1"
  bvec_ap="$2"
  bval_ap="$3"
  subj_fsl_dir="$4"
  topup_prefix="$5"
  outpref="$6"

  # Get number of volumes
  N_AP=$(fslval "$degibbs_ap" dim4 | tr -d '[:space:]')

  # create AP-only index.txt
  seq "$N_AP" | sed 's/.*/1/' > "$subj_fsl_dir/index.txt"
  echo "    index.txt (AP-only) created with $N_AP lines"

  printf "0 1 0 0.05\n" > "$subj_fsl_dir/acqparams.txt"

  echo "    running eddy_cpu on AP-only using TOPUP results"
  eddy_cpu \
    --imain="$degibbs_ap" \
    --mask="${subj_fsl_dir}/b0_brain_mask.nii.gz" \
    --acqp="$subj_fsl_dir/acqparams.txt" \
    --index="$subj_fsl_dir/index.txt" \
    --bvecs="$bvec_ap" \
    --bvals="$bval_ap" \
    --topup="$topup_prefix" \
    --fwhm=0 \
    --flm=quadratic \
    --out="$subj_fsl_dir/${outpref}_eddy" \
    --data_is_shelled
}

# ---------- main loop ----------
for subj_path in "$raw_dir"/sub-*; do
  subj=$(basename "$subj_path")
  echo "===== Processing $subj ====="

  dwi_dir="$subj_path/dwi"
  subj_mrtrix_dir="$deriv_dir/MRtrix3/$subj"
  subj_fsl_dir="$deriv_dir/fsl/$subj"
  mkdir -p "$subj_mrtrix_dir" "$subj_fsl_dir"

  DWI_AP=$(ls "$dwi_dir"/*dir-AP*_dwi.nii* 2>/dev/null | head -n1 || true)
  DWI_PA=$(ls "$dwi_dir"/*dir-PA*_dwi.nii* 2>/dev/null | head -n1 || true)

  if [ -z "$DWI_AP" ] && [ -z "$DWI_PA" ]; then
    echo "  No DWI files found for $subj -> skipping"
    continue
  fi

  # ---------- MRtrix preprocess AP ----------
  degibbs_ap=""; checked_ap_base=""; bvec_ap_to_use=""; bval_ap_to_use=""
  if [ -n "$DWI_AP" ]; then
    fname_ap=$(basename "$DWI_AP")
    base_ap="${fname_ap%.nii.gz}"; base_ap="${base_ap%.nii}"
    denoised_ap="$subj_mrtrix_dir/${base_ap}_denoised.nii.gz"
    degibbs_ap="$subj_mrtrix_dir/${base_ap}_denoised_degibbs.nii.gz"
    checked_ap_base="$subj_mrtrix_dir/${base_ap}_checked"
    bvec_ap_raw="$dwi_dir/${base_ap}.bvec"
    bval_ap_raw="$dwi_dir/${base_ap}.bval"

    echo "  MRtrix preprocess (AP): $base_ap"
    denoise_mrtrix "$DWI_AP" "$denoised_ap"
    degibbs_mrtrix "$denoised_ap" "$degibbs_ap"

    if [ -f "$bvec_ap_raw" ] && [ -f "$bval_ap_raw" ]; then
      gradcheck_mrtrix "$degibbs_ap" "$bvec_ap_raw" "$bval_ap_raw" "$checked_ap_base"
      bvec_ap_to_use="${checked_ap_base}.bvec"
      bval_ap_to_use="${checked_ap_base}.bval"
    else
      echo "    Warning: AP bvec/bval missing; will try to use raw names (may fail)"
      bvec_ap_to_use="$bvec_ap_raw"
      bval_ap_to_use="$bval_ap_raw"
    fi
  fi

  # ---------- MRtrix preprocess PA ----------
  degibbs_pa=""; checked_pa_base=""; bvec_pa_to_use=""; bval_pa_to_use=""
  if [ -n "$DWI_PA" ]; then
    fname_pa=$(basename "$DWI_PA")
    base_pa="${fname_pa%.nii.gz}"; base_pa="${base_pa%.nii}"
    denoised_pa="$subj_mrtrix_dir/${base_pa}_denoised.nii.gz"
    degibbs_pa="$subj_mrtrix_dir/${base_pa}_denoised_degibbs.nii.gz"
    checked_pa_base="$subj_mrtrix_dir/${base_pa}_checked"
    bvec_pa_raw="$dwi_dir/${base_pa}.bvec"
    bval_pa_raw="$dwi_dir/${base_pa}.bval"

    echo "  MRtrix preprocess (PA): $base_pa"
    denoise_mrtrix "$DWI_PA" "$denoised_pa"
    degibbs_mrtrix "$denoised_pa" "$degibbs_pa"

    if [ -f "$bvec_pa_raw" ] && [ -f "$bval_pa_raw" ]; then
      gradcheck_mrtrix "$degibbs_pa" "$bvec_pa_raw" "$bval_pa_raw" "$checked_pa_base"
      bvec_pa_to_use="${checked_pa_base}.bvec"
      bval_pa_to_use="${checked_pa_base}.bval"
    else
      echo "    Warning: PA bvec/bval missing; will try to use raw names (may fail)"
      bvec_pa_to_use="$bvec_pa_raw"
      bval_pa_to_use="$bval_pa_raw"
    fi
  fi

  # ---------- index_full.txt ----------
  N_AP=0; N_PA=0
  if [ -n "$degibbs_ap" ]; then N_AP=$(fslval "$degibbs_ap" dim4 | tr -d '[:space:]'); fi
  if [ -n "$degibbs_pa" ]; then N_PA=$(fslval "$degibbs_pa" dim4 | tr -d '[:space:]'); fi

  index_full="$subj_fsl_dir/index_full.txt"
  : > "$index_full"
  if [ "$N_AP" -gt 0 ]; then seq "$N_AP" | sed 's/.*/1/' >> "$index_full"; fi
  if [ "$N_PA" -gt 0 ]; then seq "$N_PA" | sed 's/.*/2/' >> "$index_full"; fi
  echo "  Created index_full.txt (AP then PA): $N_AP AP lines, $N_PA PA lines"

  # ---------- TOPUP ----------
  topup_prefix=""
  if [ -n "$degibbs_ap" ] && [ -n "$degibbs_pa" ]; then
    echo "  Running TOPUP using AP+PA degibbs B0s"
    run_topup "$degibbs_ap" "$degibbs_pa" "$subj_fsl_dir"
    topup_prefix="$subj_fsl_dir/topup_AP_PA_b0"

    required_topup_files=(
      "${topup_prefix}_fieldcoef.nii.gz"
      "${topup_prefix}_movpar.txt"
    )
    for f in "${required_topup_files[@]}"; do
        if [ ! -f "$f" ]; then
            echo "ERROR: Required TOPUP output $f not found! Cannot proceed with EDDY."
            exit 1
        fi
    done
  else
    echo "ERROR: Cannot run TOPUP (both AP and PA required). Skipping $subj."
    continue
  fi

  # ---------- EDDY ----------
  if [ -n "$degibbs_ap" ] && [ -n "$topup_prefix" ]; then
    echo "  Running EDDY_CPU on AP-only (using TOPUP results)"
    run_eddy_cpu_ap_with_topup "$degibbs_ap" "$bvec_ap_to_use" "$bval_ap_to_use" "$subj_fsl_dir" "$topup_prefix" "${subj}_AP"

    eddy_img="$subj_fsl_dir/${subj}_AP_eddy.nii.gz"
    if [ -f "$eddy_img" ]; then
        echo "  Running final BET on eddy output"
        bet "$eddy_img" "$subj_fsl_dir/${subj}_AP_eddy_brain" -m -f 0.3
    else
        echo "ERROR: EDDY output not found at $eddy_img"
        exit 1
    fi
  else
    echo "ERROR: Cannot run EDDY_CPU — either AP degibbs image or TOPUP results are missing for $subj."
    continue
  fi

  echo "===== Finished $subj ====="
done

echo "Pipeline finished."
