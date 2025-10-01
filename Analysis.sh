#!/bin/bash
set -euo pipefail

print_green() { echo -e "==> \033[1;32m$1\033[0m"; }
print_red()   { echo -e "==> \033[1;31m$1\033[0m"; }
print_yellow(){ echo -e "==> \033[1;33m$1\033[0m"; }

run_dtifit() {
    print_green "Running DTIFIT for $3"
    dtifit \
        --data="$1" \
        --mask="$2" \
        --out="$3" \
        --bvecs="$4" \
        --bvals="$5"
    print_green "DTIFIT completed for $3"
}

if [ $# -ne 1 ]; then
    print_red "Usage: $0 path/to/derivatives"
    exit 1
fi

deriv_dir="$1"
tbss_dir="${deriv_dir}/TBSS"
fsl_dir="${deriv_dir}/fsl"
mrtrix_dir="${deriv_dir}/MRtrix3"

mkdir -p "$tbss_dir"
print_green "TBSS folder prepared at $tbss_dir"

print_yellow "Checking if there are files in fsl dir"
if ls "$fsl_dir"/* >/dev/null 2>&1; then
    print_green "Files are in fsl dir"
    print_green "Preparing to run DTIFIT"

    for subject in "$fsl_dir"/*; do
        brain=$(find "$subject" -type f -name "*eddy_brain.nii.gz" | head -n1)
        mask=$(find "$subject" -type f -name "*eddy_brain_mask.nii.gz" | head -n1)
        bvecs=$(find "$subject" -type f -name "*.eddy_rotated_bvecs*" | head -n1)
        subject_num=$(basename "$subject" | grep -oE "sub-[A-Za-z0-9]+")

        if [[ $bvecs == *AP* ]]; then
            bvals=$(find "$mrtrix_dir/$subject_num" -type f -name "*AP_dwi_checked.bval" | head -n1)
        elif [[ $bvecs == *PA* ]]; then
            bvals=$(find "$mrtrix_dir/$subject_num" -type f -name "*PA_dwi_checked.bval" | head -n1)
        else
            print_red "Could not determine bvals type for $subject_num"
            continue
        fi

        subj_outdir="$tbss_dir/individual/$subject_num"
        mkdir -p "$subj_outdir"
        dti_out="$subj_outdir/${subject_num}_dti"

        print_green "Loading FSL module - version 6.0.7.16"
        ml fsl

        run_dtifit "$brain" "$mask" "$dti_out" "$bvecs" "$bvals"
    done

    ## === NEW: Gather FA and MD into group TBSS dir ===
    group_dir="$tbss_dir/group_analysis"
    mkdir -p "$group_dir/MD"
    print_green "Collecting FA and MD maps into $group_dir"

    for fa in "$tbss_dir"/individual/*/*_dti_FA.nii.gz; do
        subj=$(basename "$fa" "_dti_FA.nii.gz")
        cp "$fa" "$group_dir/${subj}_FA.nii.gz"
    done

    for md in "$tbss_dir"/individual/*/*_dti_MD.nii.gz; do
        subj=$(basename "$md" "_dti_MD.nii.gz")
        # IMPORTANT: rename MD to match FA basename (for tbss_non_FA)
        cp "$md" "$group_dir/MD/${subj}_FA.nii.gz"
    done

    ## === Run TBSS once across all subjects ===
    cd "$group_dir"
    print_green "Running TBSS - step 1"
    tbss_1_preproc *FA.nii.gz

    print_green "Running TBSS - step 2"
    tbss_2_reg -T

    print_green "Running TBSS - step 3"
    tbss_3_postreg -S

    print_green "Running TBSS - step 4"
    tbss_4_prestats 0.2

    print_green "Running TBSS non-FA for MD"
    tbss_non_FA MD

    ## === Auto-generate design.mat and design.con ===
    cd stats
    subj_count=$(ls ../FA/*FA.nii.gz | wc -l)
    if [ "$subj_count" -ge 2 ]; then
        print_green "Detected $subj_count subjects -> creating design files"

        cat > design.mat <<EOL
/NumWaves 2
/NumPoints $subj_count
/PPheights 1 1
/Matrix
1 0   # sub-003 control
0 1   # sub-011 AD
EOL

        cat > design.con <<EOL
/ContrastName1 Control-AD
/NumWaves 2
/NumContrasts 1
/Matrix
1 -1
EOL

        print_green "Running randomise"
        randomise -i all_FA_skeletonised -o tbss -m mean_FA_skeleton_mask \
                  -d design.mat -t design.con -n 500 -T

        fslmaths tbss_tfce_corrp_tstat1 -thr 0.95 sig_tstat1

        echo Subject,Mean_FA,Mean_MD > tbss_results.csv
        for fa in *_FA_skeletonised.nii.gz; do
            subj=$(basename "$fa" _FA_skeletonised.nii.gz)
            md="${subj}_MD_skeletonised.nii.gz"
            mean_fa=$(fslstats "$fa" -k mean_FA_skeleton_mask -M 2>/dev/null || echo "NA")
            if [ -f "$md" ]; then
                mean_md=$(fslstats "$md" -k mean_FA_skeleton_mask -M 2>/dev/null || echo "NA")
            else
                mean_md="NA"
            fi
            echo "$subj,$mean_fa,$mean_md" >> tbss_results.csv
        done
    else
        print_yellow "Not enough subjects for GLM/randomise"
    fi

    print_green "TBSS completed"

else
    print_red "No files in fsl dir... run preprocessing first"
fi