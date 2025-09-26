#!/bin/bash
set -euo pipefail

print_yellow() {
    echo -e "====> \033[1;33m$1\033[0m <===="
}

print_yellow "Starting Pipeline"

chmod +x data_structure_and_validation.sh
chmod +x Mriqc.sh
chmod +x Preprocessing.sh
chmod +x Analysis.sh

raw_dir="$MICROSTRUCTURE_M"/raw
deriv_dir="$ORIG_DATA"/derivatives

print_yellow "Running Data Structure and Validating Data"
./data_structure_and_validation.sh

print_yellow "Running MRIQC"
./Mriqc.sh "$raw_dir" "$deriv_dir"

print_yellow "Running Preprocessing"
./Preprocessing.sh "$raw_dir" "$deriv_dir"

print_yellow "Running Analysis"
./Analysis.sh "$deriv_dir"

print_yellow "Pipeline Completed Successfully"