#!/usr/bin/env bash

# Run a Jamf recipe.
# by Graham Pugh

# functions
usage() {
    echo "
Usage: ./jamf-recipe-run.sh [--prefs AUTOPKG_PREFS] [RECIPE | --recipe-list [AUTOPKG_RECIPE_LIST]] [-v[vvv]] [--key extra-parameters]
"
    exit 0
}

autopkg_run() {
    # Run autopkg with prefs and any extra parameters
    local RECIPE="$1"
    shift

    autopkg_cmd run "$verbosity" --prefs "$AUTOPKG_PREFS" "$RECIPE" "$@"
}

autopkg_cmd() {
    # Run autopkg with any extra parameters
    # check if the platform is ARM Mac or Ubuntu
    if [[ "$(uname)" == "Darwin" ]]; then
        autopkg "$@"
    else
        ./../autopkg/.venv/bin/python3 ../autopkg/Code/autopkg "$@"
    fi
}

## MAIN

# defaults
verbosity="-v"

# grab inputs
inputted_jamf_recipes=()
extra_key=()

while test $# -gt 0; do
    case "$1" in
    -h | --help)
        usage
        ;;
    --prefs)
        # prefs plist can be supplied. Defaults to "$HOME/Library/Preferences/com.github.autopkg.plist"
        shift
        AUTOPKG_PREFS="$1"
        [[ $AUTOPKG_PREFS == "/"* ]] || AUTOPKG_PREFS="$(pwd)/${AUTOPKG_PREFS}"
        ;;
    -r | --recipe)
        shift
        echo "Recipe: $1"
        inputted_jamf_recipes+=("$1")
        ;;
    -l | --recipe-list)
        shift
        echo "Recipe list: $1"
        AUTOPKG_RECIPE_LIST="$1"
        ;;
    --key)
        shift
        echo "Extra key: $1"
        extra_key+=(
            "--key"
            "$1"
        )
        ;;
    -v*)
        verbosity=$1
        ;;
    --replace)
        replace_pkg=1
        ;;
    *)
        echo "Unknown parameter: $1"
        usage
        ;;
    esac
    shift
done

# provide prefs
[[ $AUTOPKG_PREFS ]] || AUTOPKG_PREFS="$HOME/.config/Autopkg/config.json"
echo "AutoPkg prefs file: $AUTOPKG_PREFS"

if [[ -f "$AUTOPKG_RECIPE_LIST" ]]; then
    # create recipe list from file
    inputted_recipe_list=()
    while IFS= read -r; do
        inputted_recipe_list+=("$REPLY")
    done <"$AUTOPKG_RECIPE_LIST"
elif [[ "${#inputted_jamf_recipes[@]}" -gt 0 ]]; then
    # get list from command line
    inputted_recipe_list=("${inputted_jamf_recipes[@]}")
else
    echo "No recipe or recipe list supplied."
    usage
fi

# option to replace pkg
if [[ $replace_pkg -eq 1 ]]; then
    extra_key+=(
        "--key"
        "replace_pkg=True"
    )
fi

# GET JSS_URL from the prefs file using jq
JSS_URL=$(jq -r '.JSS_URL' "$AUTOPKG_PREFS" 2>/dev/null)
if [[ -z "$JSS_URL" ]]; then
    echo "ERROR: no URL supplied"
    exit 1
fi

# now perform the runs
for inputted_jamf_recipe in "${inputted_recipe_list[@]}"; do
    echo "Processing recipe: '$inputted_jamf_recipe'"
    extra_options=("${extra_key[@]}")

    echo "Running '$inputted_jamf_recipe' on '$JSS_URL'"
    if ! autopkg_run "$inputted_jamf_recipe" "${extra_options[@]}"; then
        echo "Recipe failed."
    fi
done
