# Copilot Instructions for autopkg-workflow-runner

## Overview

This is an AutoPkg runner for GitHub Actions that executes recipes on Linux (Ubuntu) or macOS runners. It's designed for remote triggering via GitHub's repository dispatch API, allowing external systems to trigger AutoPkg runs with dynamic credentials and recipe lists.

## Architecture

### Workflow Dispatch System

The system supports two trigger methods:

1. **Repository Dispatch** (`repository_dispatch` event) - Default method for external API triggering
2. **Workflow Dispatch** (`workflow_dispatch` event) - Manual triggering via GitHub UI or API

Both methods accept:
- A base64-encoded JSON payload containing credentials and recipe configuration
- A `runner` parameter to select between `ubuntu-latest` (default) or `macos-latest`

### AutoPkg Installation

AutoPkg installation happens directly in the workflow YAML (`autopkg-run.yml`):

**Ubuntu Setup:**
- Installs system dependencies: `git`, `jq`, `curl`, `wget`, `libcairo2-dev`, `libmagic-dev`, `p7zip-full`, `msitools`
- Installs `uv` for fast Python package management
- Clones AutoPkg from GitHub
- Creates Python 3.10 virtual environment via `uv`
- Installs **minimal runtime dependencies only**: `pyyaml`, `certifi`, `xattr`, `appdirs`
- Installs oscrypto fix for OpenSSL compatibility
- Creates config directories and verifies installation

**macOS Setup:**
- Downloads latest AutoPkg `.pkg` from GitHub releases
- Installs via `installer` command
- Creates config directories and verifies installation

**Why minimal dependencies:**
AutoPkg's `requirements.txt` includes many development tools (black, flake8, isort, pre-commit, etc.) that aren't needed for running recipes. The workflow uses only the four core runtime dependencies.

### Key Scripts

1. **setup-jamfuploader.sh** - Configures JamfUploader processors:
   - Writes credentials to AutoPkg prefs (`~/.config/Autopkg/config.json`)
   - Sets `FAIL_RECIPES_WITHOUT_TRUST_INFO = false` (no overrides workflow)
   - Adds recipe repos from supplied repo list or defaults

2. **jamf-recipe-run.sh** - Executes recipes:
   - Accepts recipes via `--recipe` flag or `--recipe-list` file
   - Supports arbitrary `--key` parameters passed to AutoPkg
   - Uses `autopkg_cmd()` wrapper to run correct AutoPkg binary for platform

3. **create-dispatch-payload.sh** - Generates dispatch payloads:
   - Base64-encodes JSON configuration files
   - Supports both `repository_dispatch` and `workflow_dispatch` formats
   - Can directly dispatch to GitHub API with `--dispatch` flag
   - Always sets runner to `ubuntu-latest` or `macos-latest`

### AutoPkg Command Wrapper

All scripts use an `autopkg_cmd()` function that detects the platform:
- **macOS**: Runs system `autopkg` command
- **Linux**: Runs `./../autopkg/.venv/bin/python3 ../autopkg/Code/autopkg`

### Credential Flow

1. External system creates JSON with `JSS_URL`, `JSS_API_USER`, `JSS_API_PW`, `GH_TOKEN`, and recipes
2. JSON is base64-encoded into dispatch payload
3. GitHub Actions decodes payload and masks all sensitive values
4. Credentials are extracted from payload (or fall back to GitHub Secrets)
5. JamfUploader is configured via `setup-jamfuploader.sh`
6. Recipes are run with credentials from AutoPkg prefs file

### Recipe Configuration

Recipes can be specified in two ways:

1. **Dynamic (via dispatch payload)**:
   - `RECIPE_1`, `RECIPE_2`, `RECIPE_N` keys in JSON
   - Any other keys (except credentials) are passed as `--key KEY=VALUE` to AutoPkg
   - Example: `"replace_pkg": "True"` becomes `--key replace_pkg=True`

2. **Static (fallback)**:
   - `recipe-list.txt` - Line-separated list of recipes
   - Used when no dispatch payload is present

## Key Conventions

### JSON Payload Keys

- **Required**: `JSS_URL`, `JSS_API_USER`, `JSS_API_PW`, `GH_TOKEN`
- **Reserved**: `RECIPE_*` (used for recipe names), `REPO_LIST` (alternative repo list file)
- **Pass-through**: All other keys become AutoPkg `--key` parameters

### Security Masking

The workflow immediately masks sensitive values using `echo "::add-mask::<value>"`:
- All credential fields from JSON payload
- All credential values from GitHub Secrets
- Values are masked before any command execution

### Platform Selection

- Default runner is `ubuntu-latest` for JamfUploader-only recipes
- Use `macos-latest` for recipes requiring macOS APIs
- Runner is selected via `inputs.runner` (workflow_dispatch) or `client_payload.runner` (repository_dispatch)
- The `create-dispatch-payload.sh` script validates that runner is either `ubuntu-latest` or `macos-latest`

### AutoPkg Repository Management

- Default repos: `grahampugh/jamf-upload`, `grahampugh-recipes`
- Custom repos can be specified via `REPO_LIST` key in payload (pointing to a text file)
- Repos are added during setup phase, before recipe execution
- The `.autopkg_repos.txt` file is used during initial setup, `repo-list.txt` as fallback

## Commands

### Generate and Dispatch a Workflow

```bash
# Create dispatch payload (Ubuntu runner)
./create-dispatch-payload.sh --input autopkg-keys.json --output dispatch-payload.json

# Create with macOS runner
./create-dispatch-payload.sh --input autopkg-keys.json --output dispatch-payload.json --platform macos-latest

# Create and immediately dispatch
./create-dispatch-payload.sh --input autopkg-keys.json --output dispatch-payload.json --dispatch --token <PAT>
```

### Manual Testing

```bash
# Setup AutoPkg (run once)
./setup.sh

# Configure JamfUploader
./setup-jamfuploader.sh \
  --jss-url "https://your.jamf.instance.com" \
  --jss-user "apiuser" \
  --jss-pass "password" \
  --github-token "ghp_token" \
  --repo-list repo-list.txt

# Run recipes
./jamf-recipe-run.sh --recipe "Firefox.jamf" --recipe "Chrome.jamf" --key replace_pkg=True
./jamf-recipe-run.sh --recipe-list recipe-list.txt -vv
```

## Testing

No automated test suite exists. Manual testing workflow:

1. Create test `autopkg-keys.json` with valid credentials
2. Generate dispatch payload: `./create-dispatch-payload.sh --input autopkg-keys.json --output test-dispatch.json`
3. Trigger workflow: Add `--dispatch --token <PAT>` or POST to GitHub API
4. Monitor workflow run in GitHub Actions tab
5. Check AutoPkg Cache output (if artifact upload is enabled)

## Important Notes

### Credential Sources

The workflow supports two credential sources (in order of precedence):

1. **GitHub Secrets** - `JSS_URL`, `JSS_API_USER`, `JSS_API_PW`, `GH_TOKEN`
2. **Dispatch Payload** - Base64-encoded JSON with same keys

If Secrets are set, they take precedence. This allows single-repo deployments to avoid sending credentials in every dispatch.

### GitHub Token Requirements

Two tokens are needed:

1. **Dispatch Token** - Used to trigger the repository_dispatch event
   - Needs `contents: read/write` and `actions: read/write` (fine-grained)
   - Or `repo` scope (classic token)

2. **GH_TOKEN** (in payload/secrets) - Used by AutoPkg to avoid GitHub API rate limits
   - Classic token with **no scopes** is sufficient
   - Prevents rate limiting when downloading from GitHub releases

### Verbosity Levels

- Default: `-v` (single verbose)
- Higher verbosity (`-vv`, `-vvv`) should **not** be used in public repos
- Risk: Credentials could leak into logs with high verbosity

### AutoPkg Prefs Location

- Linux/macOS: `~/.config/Autopkg/config.json` (JSON format)
- Not using traditional macOS plist format
