# Repository Description
This repository contains a collection of scripts developed by Team Microstructure2025-M of the CONNeXIN training program to support a longitudinal neuroimaging research study on Tract-Based Spatial Statistics (TBSS) in patients with Alzheimer’s dementia. The scripts are organized to provide an end-to-end workflow that ensures reproducibility, consistency, and efficiency in handling neuroimaging data across different stages of the study. 

# Scripts Description
-**Data Structure Organization**[ *data_structure_and_validation.sh*]: This script prepares neuroimaging data for analysis by organizing it into a BIDS-compliant dataset. It sets up the project directories, unzips and flattens subject data, runs BIDScoin to convert DICOMs, and copies pre-converted DWI files into the correct structure with BIDS naming. The script also generates metadata files and validates the dataset (ignoring warnings) to ensure consistency and usability.

-**Quality Control** [ *Mriqc.sh*]: Assesses data integrity and detect motion artifacts, missing files, or anomalies in diffusion-weighted and structural (T1w) imaging data.

-**Preprocessing** [ *Preprocessing.sh* ]: Implements preprocessing steps (e.g., eddy-current correction, brain extraction,denoising, gibbs ring removal and gradient compatibility checks) necessary to prepare diffusion MRI data for TBSS analysis.

-**Analysis** [ *Analysis.sh* ]: Executes TBSS analysis to assess changes in white matter microstructural integrity in subjects with Alzheimer’s dementia.

-**Combined** [ *run_pipeline.sh* ]: Executes the whole pipeline

## Sripts Usage
- There are two ways to use the scripts, first run the scripts individually, or run them all together using run_pipeline.sh. Either method you choose you must create two environment variables in the bash terminal
- `PROJECT_ROOT` -> Root folder name
-  `ORIG_DATA`   -> Original dataset archive

```bash
$ export PROJECT_ROOT=/home/joyvan/Microstructure_M
$ export ORIG_DATA=/home/joyvan/path/to/archive
```
=> Individual scripts method
You have to run the scripts in this order
```bash
# creates data structure and  and validate it using the bids-validator, takes no argument
$ ./data_structure_and_validation.sh
 ```
```bash
# runs quality control, takes 2 positonal arguments - raw and derivatives directories
$ ./Mriqc.sh path/to/raw path/to/derivatives
 ```

```bash
# runs preprocessing, takes 2 positonal arguments - raw and derivatives directories
$ ./Preprocessing.sh path/to/raw path/to/derivatives
 ```

```bash
# runs Anylysis, takes 1 argument - derivatives directory
$ ./Analysis.sh path/to/derivatives
 ```

=> Combined Method
```bash
# Runs all the scripts listed above, takes no arguments
$ ./run_pipeline.sh

## Team Details

### Team Lead:
- **Name:** Ahmed Kanyiri Yakubu.
- **Affiliation:** Komfo Anokye Teaching Hospital, Kumasi - Ghana.

### Team Members
1. - **Name:** Nana Yaa Doku-Amponsah.
   - **Affiliation:** University of Ghana, Accra - Ghana.

2. - **Name:** Seth Kyei Kwabena Kukudabi
   - **Affiliation:** University for Development Studies, Tamale - Ghana.
  
3. - **Name:** Jeffrey Gameli Amlalo
   - **Affiliation:** University of Cape Coast, Cape Coast - Ghana
   
4. - **Name:** Claudia Takyi Ankomah
   - **Affiliation:** Kwame Nkrumah University of Science and Technology, Kumasi - Ghana
