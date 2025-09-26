#!/bin/bash
set -euo pipefail

print_green() {
    echo -e "==> \033[1;32m$1\033[0m"
}

print_red() {
    echo -e "==> \033[1;31m$1\033[0m"
}

print_yellow() {
    echo -e "==> \033[1;33m$1\033[0m"
}

run_dtifit() {
    print_green "Running DTIFIT"
    dtifit \
        --data="$1" \
        --mask="$2" \
        --out="$3" \
        --bvecs="$4" \
        --bvals="$5"
    print_green "DTIFIT completed"
}

run_tbss(){
    print_green "Running TBSS"
    print_green "Running TBSS - step 1"
    tbss_1_preproc "$1".nii.gz

    print_green "Running TBSS - step 2"
    tbss_2_reg -T

    print_green "Running TBSS - step 3"
    tbss_3_postreg -S

    print_green "Running TBSS - step 4"
    tbss_4_prestats 0.2

    cd stats
    Glm 

    randomise -i $ALL_FA_SKELETONISED -o $TBSS -m $MEAN_FA_SKELETON_MASK -d $DESIGN.mat -t $DESIGN.con -c 1.5

    fslmaths $TBSS_TFCE_CORRP_TSTAT1 -thr 0.95 $SIG_TSTAT1

    echo Subject, Mean_FA > $TBSS_RESULTS.csv
    for subj in *_FA_SKELETONISED.nii.gz; do
        meanval=$(fslstats $subj -k $SIG_TSTAT1 -M)
        echo $(basename $subj .nii.gz),$meanval >>$TBSS_RESULTS.csv
    done
}

find_files() {
    local base_dir=$1
    local pattern=$2
    local file_name=$3

    for file in "$base_dir"/*; do 
        match=$(find "$file" -type f -name "$pattern" 2>/dev/null || true)
        if [ -n "$match" ]; then
            # print_green "Found $file_name"
            echo "$match"
        fi
    done
}

if [ $# -ne 1 ]; then
    print_red "Usage: $0 path/to/derivatives"
    exit 1
fi

deriv_dir="$1"
tbss_dir="${deriv_dir}TBSS"
fsl_dir="${deriv_dir}fsl"
mrtrix_dir="${deriv_dir}MRtrix3"

if [ -d "$tbss_dir" ]; then
    print_green "TBSS folder available"
else
    print_yellow "Creating TBSS folder"
    mkdir -p "$tbss_dir"
fi

print_yellow "Checking if there are files in fsl dir"
if ls "$fsl_dir"/* >/dev/null 2>&1; then
    print_green "Files are in fsl dir"
    print_green "Preparing to run DTIFIT"

    for subject in "$fsl_dir"/*; do
        brain=$(find_files "$subject" "*eddy_brain.nii.gz" "brain file")
        mask=$(find_files "$subject" "*eddy_brain_mask.nii.gz" "mask file")
        bvecs=$(find_files "$subject" "*.eddy_rotated_bvecs*" "bvecs")

        subject_num=$(basename "$subject" | grep -oE "sub-[0-9]+")

        if [[ $bvecs == *AP* ]]; then
            bvals=$(find_files "$mrtrix_dir/$subject_num" "*AP_dwi_checked.bval" "bvals")
        elif [[ $bvecs == *PA* ]]; then
            bvals=$(find_files "$mrtrix_dir/$subject_num" "*PA_dwi_checked.bval" "bvals")
        else
            print_red "Could not determine bvals type for $subject_num"
            continue
        fi

        dti_out="${subject_num}_dti"

        print_green "Loading FSL module - version 6.0.7.16"
        ml fsl/6.0.7.16

        echo "$bvals"
        echo "$bvecs"

        run_dtifit "$brain" "$mask" "$dti_out" "$bvecs" "$bvals"
    done
else
    print_red "No files in fsl dir... run the preprocessing script before running analysis"
fi
