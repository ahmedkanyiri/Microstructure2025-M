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

    cd "$1" 

    print_green "Running TBSS - step 1"
    tbss_1_preproc "$1".nii.gz

    print_green "Running TBSS - step 2"
    tbss_2_reg -T 

    print_green "Running TBSS - step 3"
    tbss_3_postreg -S

    print_green "Running TBSS - step 4"
    tbss_4_prestats 0.2

    cd stats

    subj_count=$(ls ../FA/*_FA_FA.nii.gz 2>/dev/null | wc -l)

    if [ "$subj_count" -gt 1 ]; then

        print_green "Detected $subj_count subjects -> running GLM + randomise"

        if [ ! -f design.mat ] || [ ! -f design.con ]; then
            print_red "No design.mat / design.con found. Create them before running group stats."
            exit 1
        fi

        randomise -i all_FA_skeletonised -o tbss -m mean_FA_skeleton_mask \
                  -d design.mat -t design.con -n 500 -T

        fslmaths tbss_tfce_corrp_tstat1 -thr 0.95 sig_tstat1

        echo Subject,Mean_FA > tbss_results.csv
        for subj in *_FA_skeletonised.nii.gz; do
            meanval=$(fslstats $subj -k sig_tstat1 -M)
            echo "$(basename $subj .nii.gz),$meanval" >> tbss_results.csv
        done

    else
        print_yellow "Only one subject found -> skipping GLM/randomise"

        echo Subject,Mean_FA,Mean_MD > tbss_results.csv
        subj=$(ls *_FA_skeletonised.nii.gz | head -n 1)

        if [ -n "$subj" ]; then
            mean_fa=$(fslstats "$subj" -M)
        else
            mean_fa="NA"
        fi

        subj_md=$(echo "$subj" | sed 's/_FA_/_MD_/')
        if [ -f "$subj_md" ]; then
            mean_md=$(fslstats "$subj_md" -M)
        else
            mean_md="NA"
        fi

        echo "$(basename $subj .nii.gz),$mean_fa,$mean_md" >> tbss_results.csv
    fi

    print_green "TBSS completed"
}

find_files() {
    local base_dir=$1
    local pattern=$2

    for file in "$base_dir"/*; do 
        match=$(find "$file" -type f -name "$pattern" 2>/dev/null || true)
        if [ -n "$match" ]; then
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
        brain=$(find_files "$subject" "*eddy_brain.nii.gz")
        mask=$(find_files "$subject" "*eddy_brain_mask.nii.gz")
        bvecs=$(find_files "$subject" "*.eddy_rotated_bvecs*")

        subject_num=$(basename "$subject" | grep -oE "sub-[0-9]+")


        if [[ $bvecs == *AP* ]]; then
            bvals=$(find_files "$mrtrix_dir/$subject_num" "*AP_dwi_checked.bval")
        elif [[ $bvecs == *PA* ]]; then
            bvals=$(find_files "$mrtrix_dir/$subject_num" "*PA_dwi_checked.bval")
        else
            print_red "Could not determine bvals type for $subject_num"
            continue
        fi

        subject_dir="$tbss_dir/$subject_num"
        mkdir -p "$subject_dir"
        dti_out="$subject_dir/${subject_num}_dti"

        print_green "Loading FSL module - version 6.0.7.16"
        ml fsl

        echo "$bvals"
        echo "$bvecs"

        run_dtifit "$brain" "$mask" "$dti_out" "$bvecs" "$bvals"

        # cd "$subject_dir/"
        # echo pwd: "$(pwd)"
        run_tbss "$subject_dir/" "$dti_out"
    done
else
    print_red "No files in fsl dir... run the preprocessing script before running analysis"
fi
