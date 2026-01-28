#!/usr/bin/env bash

# setup-jamfuploader.sh
# by Graham Pugh

# setup-jamfuploader automates the installation of the latest version
# prerequisites for using JamfUploader processors with AutoPkg.

# Acknowledgements
# Original of this file is at https://github.com/grahampugh/AutoPkgSetup
# Excerpts from https://github.com/grahampugh/run-munki-run
# which in turn borrows from https://github.com/tbridge/munki-in-a-box

configureJamfUploader() {
    # configure JamfUploader
    jq --arg jss_url "$JSS_URL" '.JSS_URL = $jss_url' "$AUTOPKG_PREFS" > "$AUTOPKG_PREFS.tmp" && mv "$AUTOPKG_PREFS.tmp" "$AUTOPKG_PREFS"

    # get API user
    if [[ "${JSS_API_USER}" ]]; then
        jq --arg api_user "$JSS_API_USER" '.API_USERNAME = $api_user' "$AUTOPKG_PREFS" > "$AUTOPKG_PREFS.tmp" && mv "$AUTOPKG_PREFS.tmp" "$AUTOPKG_PREFS"
    else
        echo "ERROR: JSS_API_USER is required to configure JamfUploader."
        exit 1
    fi

    # get API user's password
    if [[ "${JSS_API_PW}" ]]; then
        jq --arg api_pw "$JSS_API_PW" '.API_PASSWORD = $api_pw' "$AUTOPKG_PREFS" > "$AUTOPKG_PREFS.tmp" && mv "$AUTOPKG_PREFS.tmp" "$AUTOPKG_PREFS"
    else
        echo "ERROR: JSS_API_PW is required to configure JamfUploader."
        exit 1
    fi

    # JamfUploader requires simple keys for the repo if not using a cloud distribution point
    if [[ "${SMB_URL}" ]]; then
        jq --arg smb_url "$SMB_URL" '.SMB_URL = $smb_url' "$AUTOPKG_PREFS" > "$AUTOPKG_PREFS.tmp" && mv "$AUTOPKG_PREFS.tmp" "$AUTOPKG_PREFS"
    fi
    if [[ "${SMB_USERNAME}" ]]; then
        jq --arg smb_user "$SMB_USERNAME" '.SMB_USERNAME = $smb_user' "$AUTOPKG_PREFS" > "$AUTOPKG_PREFS.tmp" && mv "$AUTOPKG_PREFS.tmp" "$AUTOPKG_PREFS"
    fi
    if [[ "${SMB_PASSWORD}" ]]; then
        jq --arg smb_pw "$SMB_PASSWORD" '.SMB_PASSWORD = $smb_pw' "$AUTOPKG_PREFS" > "$AUTOPKG_PREFS.tmp" && mv "$AUTOPKG_PREFS.tmp" "$AUTOPKG_PREFS"
    fi
}

configureSlack() {
    # get Slack user and webhook
    if [[ "${SLACK_USERNAME}" ]]; then
        jq --arg slack_user "$SLACK_USERNAME" '.SLACK_USERNAME = $slack_user' "$AUTOPKG_PREFS" > "$AUTOPKG_PREFS.tmp" && mv "$AUTOPKG_PREFS.tmp" "$AUTOPKG_PREFS"
        echo "### Wrote SLACK_USERNAME $SLACK_USERNAME to $AUTOPKG_PREFS"
    fi
    if [[ "${SLACK_WEBHOOK}" ]]; then
        jq --arg slack_webhook "$SLACK_WEBHOOK" '.SLACK_WEBHOOK = $slack_webhook' "$AUTOPKG_PREFS" > "$AUTOPKG_PREFS.tmp" && mv "$AUTOPKG_PREFS.tmp" "$AUTOPKG_PREFS"
        echo "### Wrote SLACK_WEBHOOK $SLACK_WEBHOOK to $AUTOPKG_PREFS"
    fi
}

autopkg_cmd() {
    # Run autopkg with any extra parameters
    ./../autopkg/.venv/bin/python3 ../autopkg/Code/autopkg "$@"
}

## Main section

# declare array for recipe lists
AUTOPKG_RECIPE_LISTS=()

# get arguments
while test $# -gt 0
do
    case "$1" in
        --github-token)
            shift
            GITHUB_TOKEN="$1"
        ;;
        --recipe-list)
            shift
            AUTOPKG_RECIPE_LISTS+=("$1")
        ;;
        --repo-list)
            shift
            AUTOPKG_REPO_LIST="$1"
        ;;
        --smb-url)
            shift
            SMB_URL="$1"
        ;;
        --smb-user)
            shift
            SMB_USERNAME="$1"
        ;;
        --smb-pass)
            shift
            SMB_PASSWORD="$1"
        ;;
        --jss-url)
            shift
            JSS_URL="$1"
        ;;
        --jss-user)
            shift
            JSS_API_USER="$1"
        ;;
        --jss-pass)
            shift
            JSS_API_PW="$1"
        ;;
        --slack-webhook)
            shift
            SLACK_WEBHOOK="$1"
        ;;
        --slack-user)
            shift
            SLACK_USERNAME="$1"
        ;;
        *)
            echo "
Usage:
./setup-jamfuploader.sh                           

-h | --help             Displays this text
--github-token *        A GitHub token - required to prevent hitting API limits

--repo-list *           Path to a repo-list file. All repos will be added to the prefs file.

--recipe-list *         Path to a recipe list. If this method is used, all parent repos
                        are added, but the recipes must be in a repo that is already installed.

--jss-url *             URL of the Jamf server
--jss-user *            API account username
--jss-pass *            API account password

JamfUploader settings:

--smb-url *        URL of the FileShare Distribution Point
--smb-user *       Username of account that has access to the DP
--smb-pass *       Password of account that has access to the DP

Slack settings:

--slack-webhook *       Slack webhook
--slack-user *          A display name for the Slack notifications

"
            exit 0
        ;;
    esac
    shift
done

# define autopkg prefs path
AUTOPKG_PREFS="$HOME/.config/Autopkg/config.json"

# add the GIT path to the prefs
jq --arg git_path "$(which git)" '.GIT_PATH = $git_path' "$AUTOPKG_PREFS" > "$AUTOPKG_PREFS.tmp" && mv "$AUTOPKG_PREFS.tmp" "$AUTOPKG_PREFS"
echo "### Wrote GIT_PATH $(which git) to $AUTOPKG_PREFS"

# add the GitHub token to the prefs
if [[ $GITHUB_TOKEN ]]; then
    jq --arg github_token "$GITHUB_TOKEN" '.GITHUB_TOKEN = $github_token' "$AUTOPKG_PREFS" > "$AUTOPKG_PREFS.tmp" && mv "$AUTOPKG_PREFS.tmp" "$AUTOPKG_PREFS"
    echo "### Wrote GITHUB_TOKEN to $AUTOPKG_PREFS"
fi

# this workflow does not use overrides, so ensure untrusted recipes don't fail
jq '.FAIL_RECIPES_WITHOUT_TRUST_INFO = false' "$AUTOPKG_PREFS" > "$AUTOPKG_PREFS.tmp" && mv "$AUTOPKG_PREFS.tmp" "$AUTOPKG_PREFS"
echo "### Wrote FAIL_RECIPES_WITHOUT_TRUST_INFO false to $AUTOPKG_PREFS"

# add Slack credentials if anything supplied
if [[ $SLACK_USERNAME || $SLACK_WEBHOOK ]]; then
    configureSlack
fi

if [[ $JSS_URL ]]; then
    # Configure JamfUploader
    configureJamfUploader
    echo "### JamfUploader configured."
fi

# Add recipe repos to the prefs.
if [[ -f "$AUTOPKG_REPO_LIST" ]]; then
    while read -r -d '' AUTOPKGREPO; do
        autopkg_cmd repo-add "$AUTOPKGREPO" --prefs "$AUTOPKG_PREFS"
        echo "Added $AUTOPKGREPO to the prefs file"
    done < "$AUTOPKG_REPO_LIST"
else
    repo_list=(
        grahampugh/jamf-upload
        grahampugh-recipes
    )
    while read -r -d '' AUTOPKGREPO; do
        autopkg_cmd repo-add "$AUTOPKGREPO" --prefs "$AUTOPKG_PREFS"
        echo "Added $AUTOPKGREPO to the prefs file"
    done < <(printf '%s\0' "${repo_list[@]}")

fi

echo "### AutoPkg Repos Added"

