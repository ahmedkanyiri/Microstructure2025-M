#!/bin/bash
set -euo pipefail

print_yellow() {
    echo -e "==> \033[1;33m$1\033[0m <=="
}

print_yellow "Starting Pipeline"

chmod +x data_structure_and_validation.sh
chmod +x Mriqc.sh
chmod +x Preprocessing.sh
chmod +x Analysis.sh

print_yellow "Running Data Structure and Validating Data"
./data_structure_and_validation.sh

print_yellow "Running MRIQC"
./Mriqc.sh

print_yellow "Running Preprocessing"
./Preprocessing.sh

print_yellow "Running Analysis"
./Analysis.sh