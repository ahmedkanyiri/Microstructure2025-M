#!/bin/bash

# Usage:
# Set environment variables by exporting them before running the script:
#   export PROJECT_ROOT=/path/to/project/root
#   export ORIG_DATA=/path/to/orig_or_zip_parent
#   ./data_structure_and_validation.sh

# Or inline when running the script:
# PROJECT_ROOT=/path/to/project ORIG_DATA=/path/to/orig_or_zip_parent ./data_structure_and_validation.sh

set -euo pipefail
IFS=$'\n\t'

# --- Colors ---
print_green() { echo -e "==> \033[1;32m$1\033[0m"; }
print_red()   { echo -e "==> \033[1;31m$1\033[0m"; }
print_yellow(){ echo -e "==> \033[1;33m$1\033[0m"; }

# --- Config ---
: "${PROJECT_ROOT:?"Please set PROJECT_ROOT (project root)"}"
: "${ORIG_DATA:?"Please set ORIG_DATA (original data path)"}"

SOURCE="source"
RAW="raw"
DERIVATIVES="derivatives"
CODE="code"
REQ_BIDSCOIN_VER="4.6.2"

SUB_LIST="${PROJECT_ROOT}/sub_list"

# --- Functions ---
create_dirs() {
    print_green "Creating project directories"
    mkdir -p "$PROJECT_ROOT"/{$SOURCE,$RAW,$DERIVATIVES}
}

populate_source() {
    print_green "Populating source from $ORIG_DATA"
    mkdir -p "$PROJECT_ROOT/$SOURCE"
    pushd "$PROJECT_ROOT/$SOURCE" >/dev/null

    if [ -f "$ORIG_DATA" ] && [[ "$ORIG_DATA" == *.zip ]]; then
        unzip -o "$ORIG_DATA"
    elif [ -d "$ORIG_DATA" ]; then
        rsync -a "$ORIG_DATA"/sub-* ./ 2>/dev/null || true
        for z in "$ORIG_DATA"/*.zip; do
            [ -e "$z" ] && unzip -o "$z"
        done
    fi

    # Flatten wrapper dirs (e.g. orig_data/sub-*)
    for nested in */sub-*; do
        [ -d "$nested" ] && mv "$nested" .
    done

    popd >/dev/null

    if [ -f "$SUB_LIST" ]; then
        print_yellow "Subjects loaded from sub_list:"
        cat "$SUB_LIST"
    else
        print_yellow "Subjects found in source:"
        find "$PROJECT_ROOT/$SOURCE" -maxdepth 2 -type d -name "sub-*" || true
    fi
}

load_bidscoin() {
    print_green "Checking for BIDScoin"

    if command -v ml >/dev/null; then
        print_yellow "Trying to load bidscoin module"
        ml bidscoin/$REQ_BIDSCOIN_VER || print_yellow "Module load failed"
    fi

    if command -v bidscoin >/dev/null; then
        ver=$(bidscoin --version || true)
        print_green "Found bidscoin version: ${ver:-unknown}"
    else
        print_red "BIDScoin not found in PATH"
    fi
}

run_bidsmapper() {
    local src="$PROJECT_ROOT/$SOURCE"
    local raw="$PROJECT_ROOT/$RAW"
    mkdir -p "$raw/$CODE/bidscoin"

    if [["$GOOGLE_COLAB" == "True"]]; then
        auto="-a"
    else 
        auto=""
    fi 

    if command -v bidsmapper >/dev/null; then
        print_green "Running bidsmapper"
        bidsmapper "$src" "$raw" "$auto" || print_yellow "bidsmapper failed"
    else
        print_yellow "bidsmapper not found"
    fi
}

run_bidscoiner() {
    local src="$PROJECT_ROOT/$SOURCE"
    local raw="$PROJECT_ROOT/$RAW"

    if command -v bidscoiner >/dev/null; then
        print_green "Running bidscoiner"
        bidscoiner "$src" "$raw" || print_yellow "bidscoiner failed"
    else
        print_yellow "bidscoiner not found"
    fi
}

copy_existing_dwi() {
    local src="$PROJECT_ROOT/$SOURCE"
    local raw="$PROJECT_ROOT/$RAW"

    print_green "Copying pre-converted DWI files"

    if [ -f "$SUB_LIST" ]; then
        subjects=$(cat "$SUB_LIST")
    else
        subjects=$(find "$raw" -maxdepth 1 -type d -name "sub-*" -print0 2>/dev/null | xargs -0 -n1 basename || true)
    fi

    for subj in $subjects; do
        subjdir="$raw/$subj"
        [ -d "$subjdir" ] || continue

        src_dwi=$(find "$src" -type d -path "*/${subj}_*/dwi" | head -n1)
        if [ -z "$src_dwi" ] || [ ! -d "$src_dwi" ]; then
            print_yellow "  No DWI folder found for $subj (looked for ${subj}_*/dwi)"
            continue
        fi

        target="$subjdir/dwi"
        mkdir -p "$target"

        for acq in AP PA; do
            nifti=$(find "$src_dwi" -maxdepth 1 -type f -name "*_${acq}_dwi.nii*" | head -n1)
            if [ -z "$nifti" ]; then
                print_yellow "  No ${acq} DWI found for $subj"
                continue
            fi

            if [[ "$nifti" == *.nii.gz ]]; then
                base_src="${nifti%.nii.gz}"
                nii_ext="nii.gz"
            else
                base_src="${nifti%.nii}"
                nii_ext="nii"
            fi

            base="${subj}_dir-${acq}_dwi"
            print_yellow "  Copying ${acq} DWI for $subj -> $target/${base}.*"

            for ext in "$nii_ext" bval bvec json; do
                fsrc="${base_src}.$ext"
                if [ -f "$fsrc" ]; then
                    cp -v "$fsrc" "$target/${base}.$ext"
                else
                    print_yellow "    Missing: $fsrc"
                fi
            done
        done
    done
}


add_bidsignore() {
    local raw="$PROJECT_ROOT/$RAW"
    cat > "$raw/.bidsignore" <<EOF
raw/${CODE}/
raw/README
raw/*.errors
raw/*.log
EOF
}

write_dataset_description() {
    local raw="$PROJECT_ROOT/$RAW"
    cat > "$raw/dataset_description.json" <<EOF
{
  "Name": "Microstructure-M Pipeline Dataset",
  "BIDSVersion": "1.9.0",
  "Authors": ["Microstructure-M Team"]
}
EOF
}

run_bids_validator() {
    local raw="$PROJECT_ROOT/$RAW"
    if command -v deno >/dev/null; then
        print_green "Running BIDS validator (ignoring warnings, verbose mode)"
        deno run -ERWN jsr:@bids/validator "$raw" --ignoreWarnings --verbose || print_yellow "Validator issues found"
    else
        print_yellow "deno not found, skipping validation"
    fi
}

show_tree() {
    local raw="$PROJECT_ROOT/$RAW"
    if command -v tree >/dev/null; then
        tree -L 4 "$raw"
    else
        find "$raw" -maxdepth 4
    fi
}

# --- Main ---
print_green "Starting Microstructure-M BIDScoin pipeline"

create_dirs
populate_source
load_bidscoin
run_bidsmapper
run_bidscoiner
copy_existing_dwi
add_bidsignore
write_dataset_description
run_bids_validator
show_tree

print_green "Data Structure and Validation complete"
