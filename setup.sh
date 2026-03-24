#!/usr/bin/env bash

# Script to set up AutoPkg on a Debian-based or Mac runner
# Based on https://github.com/jgstew/jgstew-recipes/blob/main/setup_ubuntu.sh
# and
# https://github.com/stilljake/serverless-munki/blob/master/.github/workflows/autopkg-run.yml

## FUNCTIONS

setup_ubuntu() {
    echo "Running on Linux - performing Ubuntu setup"

    uv python install 3.10

    sudo apt update && DEBIAN_FRONTEND=noninteractive apt install -y git

    # install packages needed for installing python requirements and using python processors
    sudo DEBIAN_FRONTEND=noninteractive apt install -y speech-dispatcher libcairo2-dev libmagic-dev jq p7zip-full msitools curl wget

    # if autopkg does not exist
    if [ ! -f ../autopkg ]; then
        git clone https://github.com/autopkg/autopkg.git ../autopkg
    fi

    # create virtual environment using uv
    uv venv --python 3.10 ../autopkg/.venv

    # install minimal autopkg runtime dependencies
    uv pip install --python ../autopkg/.venv/bin/python3 \
        pyyaml certifi xattr appdirs

    # install jgstew-recipes requirements (if requirements.txt exists):
    if [[ -f requirements.txt ]]; then
        uv pip install --python ../autopkg/.venv/bin/python3 \
            --requirement requirements.txt
    fi

    # fix issue with new openssl and a processor
    # https://github.com/wbond/oscrypto/issues/78#issuecomment-2210120532
    uv pip install --python ../autopkg/.venv/bin/python3 \
        git+https://github.com/wbond/oscrypto.git

}

setup_mac() {
    echo "Running on macOS - performing macOS setup"

    # Get AutoPkg
    # thanks to Nate Felton
    # Inputs: 1. $USERHOME
    echo "### Downloading AutoPkg installer package..."
    echo
    # Use the public API if no token is provided
    AUTOPKG_PKG=$(curl -sL -H "Accept: application/json" "https://api.github.com/repos/autopkg/autopkg/releases/latest" | awk -F '"' '/browser_download_url/ { print $4; exit }')

    if ! /usr/bin/curl -L "${AUTOPKG_PKG}" -o "/tmp/autopkg-latest.pkg"; then
        echo "### ERROR: could not obtain AutoPkg installer package..."
        echo
        exit 1
    fi

    if ! sudo installer -pkg /tmp/autopkg-latest.pkg -target /; then
        echo "### ERROR: could not install AutoPkg..."
        echo
        exit 1
    fi

    autopkg_version=$(autopkg version)

    if [[ -z "$autopkg_version" ]]; then
        echo "### ERROR: could not determine AutoPkg version after installation..."
        echo
        exit 1
    fi

    echo "AutoPkg $autopkg_version Installed"
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

## MAIN SETUP

# prevent sudo from asking for password if already root and no sudo available like in docker
if [ ${EUID:-0} -ne 0 ] || [ "$(id -u)" -ne 0 ]; then
    echo ""
else
    # if already root and no sudo available like in docker:
    sudo() { "$@"; }
fi

# check if the platform is ARM Mac or Ubuntu
if [[ "$(uname)" == "Darwin" ]]; then
    setup_mac
else
    setup_ubuntu
fi

# create folder for autopkg recipe map
mkdir -p ~/Library/AutoPkg

# create folder for autopkg config
mkdir -p ~/.config/Autopkg

# if config file does not exist, create it:
if [[ ! -f ~/.config/Autopkg/config.json ]]; then
    echo {} >~/.config/Autopkg/config.json
fi

# add required recipe repos for jgstew-recipes
while IFS= read -r line; do
    autopkg_cmd repo-add "$line"
done <.autopkg_repos.txt

# get autopkg version
autopkg_cmd version

echo "Setup complete."
exit 0
