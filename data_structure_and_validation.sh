#!/bin/bash
# data_structure.sh
# Full pipeline: create project dirs, extract original data, run BIDScoin (bidsmapper/bidscoiner),
# write .bidsignore and dataset_description.json, attempt BIDS validator.
#
# Usage:
#   export MICROSTRUCTURE_M=/path/to/project
#   export ORIG_DATA=/path/to/orig_or_zip_parent
#   ./data_structure.sh
#
set -euo pipefail
IFS=$'\n\t'

############ USER CONFIGURABLE ############
: "${MICROSTRUCTURE_M:?"Please set MICROSTRUCTURE_M (project root) environment variable"}"
: "${ORIG_DATA:?"Please set ORIG_DATA (original data root; can be a directory or a zip file)"}"

SOURCE="source"         # original DICOMs go here (under $MICROSTRUCTURE_M)
RAW="raw"               # BIDS output (under $MICROSTRUCTURE_M)
DERIVATIVES="derivatives"

REQ_BIDSCOIN_VER="4.6.2"
SUB_GLOB="sub-*"

# BIDScoin code dir name (bidscoin creates $RAW/<CODE>/bidscoin/)
CODE="code"
# possible bidsmap locations (bidscoin sometimes creates bidsmap.yaml or .bidsmap.yaml)
BIDSMAP_CAND1="${MICROSTRUCTURE_M}/${RAW}/${CODE}/bidscoin/bidsmap.yaml"
BIDSMAP_CAND2="${MICROSTRUCTURE_M}/${RAW}/${CODE}/bidscoin/.bidsmap.yaml"

###########################################

info()  { printf "\n[INFO] %s\n" "$*"; }
warn()  { printf "\n[WARN] %s\n" "$*"; }
err()   { printf "\n[ERROR] %s\n" "$*" >&2; exit 1; }

check_cmd() { command -v "$1" >/dev/null 2>&1; }

create_dirs() {
  info "Creating project directories under: $MICROSTRUCTURE_M"
  mkdir -p "$MICROSTRUCTURE_M"/{$SOURCE,$RAW,$DERIVATIVES}
  info "Created: $MICROSTRUCTURE_M/{$SOURCE,$RAW,$DERIVATIVES}"
  ls -1 "$MICROSTRUCTURE_M" || true
}

populate_source() {
  info "Populating $MICROSTRUCTURE_M/$SOURCE from $ORIG_DATA"
  mkdir -p "$MICROSTRUCTURE_M/$SOURCE"
  pushd "$MICROSTRUCTURE_M/$SOURCE" >/dev/null

  # If ORIG_DATA is a zip file -> unzip it here
  if [ -f "$ORIG_DATA" ] && [[ "$ORIG_DATA" == *.zip ]]; then
    info "Unzipping $ORIG_DATA into $MICROSTRUCTURE_M/$SOURCE"
    unzip -o "$ORIG_DATA"
  fi

  # If ORIG_DATA is a directory -> copy sub-* dirs and unzip any zips inside
  if [ -d "$ORIG_DATA" ]; then
    info "Copying sub-* directories (if any) from $ORIG_DATA"
    shopt -s nullglob
    for d in "$ORIG_DATA"/$SUB_GLOB; do
      if [ -d "$d" ]; then
        info "Copying directory: $d"
        rsync -a --progress "$d" ./
      fi
    done

    # unzip any subject zip files in ORIG_DATA
    for z in "$ORIG_DATA"/*.zip; do
      [ -e "$z" ] || break
      info "Unzipping $z into $MICROSTRUCTURE_M/$SOURCE"
      unzip -o "$z"
    done
  fi

  popd >/dev/null

  info "Subjects found in $MICROSTRUCTURE_M/$SOURCE:"
  find "$MICROSTRUCTURE_M/$SOURCE" -maxdepth 2 -type d -name "sub-*" -print || true
}

load_bidscoin() {
  info "Attempting to load bidscoin v$REQ_BIDSCOIN_VER"
  if check_cmd ml; then
    info "Module system detected: trying 'ml bidscoin/$REQ_BIDSCOIN_VER'"
    ml bidscoin/"$REQ_BIDSCOIN_VER" || warn "ml failed or returned non-zero; continuing to check bidscoin in PATH"
  fi

  if check_cmd bidscoin; then
    ver="$(bidscoin --version || true)"
    info "bidscoin --version => ${ver:-(no output)}"
    if [[ "$ver" != *"$REQ_BIDSCOIN_VER"* ]]; then
      warn "bidscoin version mismatch: expected $REQ_BIDSCOIN_VER but found: $ver"
    fi
  else
    warn "bidscoin not found in PATH. If running NeuroDesk GUI-only, use the GUI or ensure bidsmapper/bidscoiner are available."
  fi
}

run_bidsmapper() {
  local src="$MICROSTRUCTURE_M/$SOURCE"
  local raw="$MICROSTRUCTURE_M/$RAW"
  info "Running bidsmapper: scanning DICOMs -> mapping draft"
  mkdir -p "$raw/$CODE/bidscoin"

  if check_cmd bidsmapper; then
    info "Invoking: bidsmapper \"$src\" \"$raw\""
    bidsmapper "$src" "$raw"
  else
    warn "bidsmapper not found. If BIDScoin exists only via GUI (NeuroDesk), please run bidsmapper there and save the bidsmap.yaml to $raw/$CODE/bidscoin/"
  fi

  # detect mapping file (bidsmap.yaml or .bidsmap.yaml)
  if [ -f "$BIDSMAP_CAND1" ]; then
    BIDSMAP_PATH="$BIDSMAP_CAND1"
  elif [ -f "$BIDSMAP_CAND2" ]; then
    BIDSMAP_PATH="$BIDSMAP_CAND2"
  else
    BIDSMAP_PATH=""
  fi

  if [ -n "$BIDSMAP_PATH" ]; then
    info "Mapping file created: $BIDSMAP_PATH"
  else
    warn "Mapping file not found at $BIDSMAP_CAND1 or $BIDSMAP_CAND2. If GUI opened, please Save -> File->Save in BIDS Editor, or place your bidsmap.yaml at $raw/$CODE/bidscoin/"
  fi
}

auto_modify_bidsmap() {
  local map="${BIDSMAP_PATH:-}"
  if [ -z "$map" ]; then
    warn "No mapping file to modify. Skipping auto-edit step."
    return
  fi

  info "Attempting to modify mapping file: $map (best-effort automatic edits)"

  if check_cmd yq; then
    info "Using yq to patch YAML"
    # Set patient id regex and clear sesprefix; remove '-i' from args; clear acq/run where present
    yq eval '
      (.participants.patient_id) = "<<filepath:/source/sub-([0-9]+)>>" |
      (.options.sesprefix) = "" |
      (.options.args) |= (if type == "string" then sub("-i","") else . end)
    ' -i "$map" || warn "yq edit had issues; continuing"

    # Clear acq and run fields if present anywhere
    yq eval '... comments="" | .. | select(has("acq")) .acq = "" | .. | select(has("run")) .run = ""' -i "$map" || true
  else
    info "yq not found — applying text-based best-effort edits (perl fallback)"
    perl -0777 -pe 's/(patient_id\s*:\s*).*/$1<<filepath:\/source\/sub-([0-9]+)>>/i' -i "$map" || true
    perl -0777 -pe 's/(sesprefix\s*:\s*).*/$1""/i' -i "$map" || true
    perl -0777 -pe 's/\-i\s*//g' -i "$map" || true
    perl -0777 -pe 's/(acq\s*:\s*).*/$1""/ig; s/(run\s*:\s*).*/$1""/ig' -i "$map" || true
  fi

  info "Automated edits applied (best-effort). It's recommended to open the mapping in the BIDS Editor for visual verification."
  if check_cmd bidseditor; then
    info "To open BIDS Editor: bidseditor \"$map\""
  fi
}

run_bidscoiner() {
  local src="$MICROSTRUCTURE_M/$SOURCE"
  local raw="$MICROSTRUCTURE_M/$RAW"

  info "Running bidscoiner to convert $src -> $raw"
  if check_cmd bidscoiner; then
    bidscoiner "$src" "$raw"
  else
    warn "bidscoiner executable not found. If you have only the NeuroDesk GUI, run conversion there or make bidscoiner available in PATH."
  fi

  info "After bidscoiner run, check that $raw contains subject sub-* folders with anat/ and dwi/ etc."
  find "$raw" -maxdepth 2 -type d -name "sub-*" -print || true
}

add_bidsignore() {
  local raw="$MICROSTRUCTURE_M/$RAW"
  local f="$raw/.bidsignore"
  info "Creating .bidsignore at $f"
  cat > "$f" <<EOF
raw/${CODE}/
raw/README
raw/*.errors
raw/*.log
EOF
  info ".bidsignore content:"
  sed -n '1,200p' "$f" || true
}

write_dataset_description() {
  local raw="$MICROSTRUCTURE_M/$RAW"
  local f="$raw/dataset_description.json"
  info "Writing minimal dataset_description.json to $f"
  cat > "$f" <<EOF
{
  "Name": "Microstructure-M Pipeline Dataset",
  "BIDSVersion": "1.9.0",
  "Authors": ["Microstructure-M Team"]
}
EOF
  info "dataset_description.json written."
}

run_bids_validator() {
  local raw="$MICROSTRUCTURE_M/$RAW"
  info "Checking for deno (required for the Deno-based @bids/validator)"

  if ! check_cmd deno; then
    warn "deno not found. Attempting non-interactive install (requires curl & sh)."
    if check_cmd curl && check_cmd sh; then
      curl -fsSL https://deno.land/install.sh | sh || warn "deno install failed; skipping validator run."
      export PATH="$HOME/.deno/bin:$PATH"
    else
      warn "curl/sh not available — cannot install deno automatically. Please install deno manually to run validator."
      return
    fi
  fi

  if check_cmd deno; then
    info "Running BIDS validator on: $raw"
    # Try the recommended invocation; tolerate non-zero exit but print output
    deno run -ERWN jsr:@bids/validator "$raw" || warn "Validator returned non-zero or failed. Inspect output above for Errors/Warnings."
  else
    warn "deno still not available — skipping validator"
  fi
}

show_tree() {
  local raw="$MICROSTRUCTURE_M/$RAW"
  info "Final directory tree for $raw (top 4 levels):"
  if check_cmd tree; then
    tree -L 4 "$raw" || true
  else
    find "$raw" -maxdepth 4 -print | sed 's|^|  |g' || true
  fi
}

########## Main ##########
info "Starting Microstructure-M BIDScoin pipeline"

create_dirs
populate_source
load_bidscoin
run_bidsmapper

# after bidsmapper, check BIDSMAP_PATH found in function; if present, auto-modify
auto_modify_bidsmap

# run conversion
run_bidscoiner

# create .bidsignore and dataset_description.json
add_bidsignore
write_dataset_description

# attempt validation (best-effort)
run_bids_validator

# summary tree
show_tree

info "Pipeline finished. Inspect mapping file (if created):"
if [ -n "${BIDSMAP_PATH-}" ]; then
  info "$BIDSMAP_PATH"
else
  info "No bidsmap saved automatically. You can open bidseditor to create/save it in $MICROSTRUCTURE_M/$RAW/$CODE/bidscoin/"
fi

info "If you need to open the BIDS Editor (GUI) to adjust mappings: bidseditor <path-to-bidsmap.yaml>"
