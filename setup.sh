#!/usr/bin/env bash

# Script to set up AutoPkg on a Debian-based or Mac runner
# Based on https://github.com/jgstew/jgstew-recipes/blob/main/setup_ubuntu.sh
# and
# https://github.com/stilljake/serverless-munki/blob/master/.github/workflows/autopkg-run.yml

## FUNCTIONS

setup_ubuntu() {
    echo "Running on Linux - performing Ubuntu setup"

    sudo apt update && DEBIAN_FRONTEND=noninteractive apt install -y git
    # git clone https://github.com/jgstew/jgstew-recipes.git

    # setup python3.10: https://gist.github.com/rutcreate/c0041e842f858ceb455b748809763ddb
    sudo DEBIAN_FRONTEND=noninteractive apt install -y software-properties-common git
    sudo add-apt-repository ppa:deadsnakes/ppa -y && apt update

    sudo DEBIAN_FRONTEND=noninteractive apt install -y python3.10 python3.10-venv python3.10-dev

    # https://pip.pypa.io/en/stable/installation/#ensurepip
    sudo python3.10 -m ensurepip --upgrade

    # update python pip
    sudo python3.10 -m pip install --upgrade pip

    # update python basics
    sudo python3.10 -m pip install --upgrade setuptools wheel build Foundation

    # install packages needed for installing python requirements and using python processors
    sudo DEBIAN_FRONTEND=noninteractive apt install -y python-dev-is-python3 speech-dispatcher libcairo2-dev libmagic-dev jq p7zip-full msitools curl git wget build-essential libncursesw5-dev libssl-dev libsqlite3-dev tk-dev libgdbm-dev libc6-dev libbz2-dev libffi-dev zlib1g-dev

    # if autopkg does not exist
    if [ ! -f ../autopkg ]; then
        git clone https://github.com/autopkg/autopkg.git ../autopkg
    # bash -c "cd ../autopkg && git checkout dev"
    fi

    # create virtual environment
    python3.10 -m venv ../autopkg/.venv
    ./../autopkg/.venv/bin/python3 -m pip install --upgrade pip
    ./../autopkg/.venv/bin/python3 -m pip install --upgrade setuptools wheel build

    # install autopkg requirements
    ./../autopkg/.venv/bin/python3 -m pip install --requirement ../autopkg/gh_actions_requirements.txt

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
        ./../autopkg/.venv/bin/python3 ../autopkg/Code/autopkg repo-add "$line"
    done <.autopkg_repos.txt

    # install jgstew-recipes requirements:
    ./../autopkg/.venv/bin/python3 -m pip install --requirement requirements.txt

    # fix issue with new openssl and a processor
    # https://github.com/wbond/oscrypto/issues/78#issuecomment-2210120532
    ./../autopkg/.venv/bin/python3 -m pip install -I git+https://github.com/wbond/oscrypto.git

    # get autopkg version
    ./../autopkg/.venv/bin/python3 ../autopkg/Code/autopkg version
}

setup_mac() {
    echo "Running on macOS - performing macOS setup"

    # Get AutoPkg
    # thanks to Nate Felton
    # Inputs: 1. $USERHOME
    echo "### Downloading AutoPkg installer package..."
    echo
    if [[ $use_beta == "yes" ]]; then
        tag="tags/v3.0.0RC2"
    else
        tag="latest"
    fi
    if [[ $GITHUB_TOKEN ]]; then
        # Use the GitHub token if provided
        AUTOPKG_PKG=$(curl -sL -H "Accept: application/json" -H "Authorization: Bearer ${GITHUB_TOKEN}" "https://api.github.com/repos/autopkg/autopkg/releases/$tag" | awk -F '"' '/browser_download_url/ { print $4; exit }')
    else
        # Use the public API if no token is provided
        AUTOPKG_PKG=$(curl -sL -H "Accept: application/json" "https://api.github.com/repos/autopkg/autopkg/releases/latest" | awk -F '"' '/browser_download_url/ { print $4; exit }')
    fi

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

echo "Setup complete."
exit 0
