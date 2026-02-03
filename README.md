# autopkg-workflow-runner

A proof-of-concept AutoPkg runner that executes on Linux or Mac via GitHub Actions. This is designed to allow running AutoPkg recipes on Linux that don't require macOS, such as certain recipes using JamfUploader processors, while remaining able to spin up a macOS system when required.

## Overview

This repository enables automated AutoPkg recipe runs triggered by external systems via GitHub's repository dispatch API. A website or external service can construct a JSON configuration file with Jamf Pro credentials and recipe information, which is then base64-encoded and sent to GitHub Actions to trigger an AutoPkg run.

## Features

- **Remote triggering**: Trigger AutoPkg runs via GitHub API from external systems
- **Secure credential handling**: Credentials passed via encrypted dispatch payload
- **Dynamic recipe selection**: Specify recipes and AutoPkg keys at runtime
- **Linux-based execution**: Runs on GitHub Actions Ubuntu runners
- **JamfUploader support**: Pre-configured for Jamf Pro upload workflows

## Quick Start

### 1. Create a GitHub Personal Access Token for running the dispatch

To trigger dispatches, you need a Personal Access Token:

**Using Fine-Grained Tokens (Recommended):**

1. Go to **GitHub.com** → **Settings** → **Developer settings** → **Personal access tokens** → **Fine-grained tokens**
2. Click **Generate new token**
3. Configure:
   - **Token name**: "AutoPkg Dispatch Trigger"
   - **Expiration**: Set as needed (e.g., 90 days, 1 year)
   - **Repository access**: "Only select repositories" → Select this repository
   - **Repository permissions**:
     - **Contents**: Read and write
     - **Actions**: Read and write
4. Click **Generate token** and save it securely

**Using Classic Tokens:**

1. Go to **GitHub.com** → **Settings** → **Developer settings** → **Personal access tokens** → **Tokens (classic)**
2. Click **Generate new token (classic)**
3. Select scopes:
   - `repo` (Full control of private repositories)
4. Generate and save the token securely

### 3. Prepare Your Configuration

Create an `autopkg-keys.json` file with your configuration:

```json
{
  "JSS_URL": "https://your.jamf.instance.com",
  "JSS_API_USER": "your-api-username",
  "JSS_API_PW": "your-api-password",
  "GH_TOKEN": "ghp_your_github_token",
  "RECIPE_1": "MozillaFirefox.jamf",
  "RECIPE_2": "GoogleChrome.jamf",
  "RECIPE_3": "Zoom.jamf",
  "replace_pkg": "True"
}
```

#### Required Keys

- **`JSS_URL`** - Your Jamf Pro server URL (e.g., `https://company.jamfcloud.com`)
- **`JSS_API_USER`** - API username or Client ID with whichever permissions are required to run the recipes.
- **`JSS_API_PW`** - Password for the API user or Client ID.
- **`GH_TOKEN`** - GitHub Personal Access Token. This is **not** the same token as the token required for deploying a dispatch. This is a generic token required to prevent oppressive rate limitation by GitHub. A Classic token with no scopes is sufficient.

If the runner will only be used on one repo, the key/value pairs can also be provided as secrets, meaning they don't need to be in the JSON.

#### Optional Keys

- **`RECIPE_1`, `RECIPE_2`, etc.** - Recipe names to run (e.g., `AppName.jamf`, `com.github.jamf.myrecipe`, `/path/to/SomeRecipe.jamf.recipe.yaml`)
  - Can include any number of recipes
  - Each is passed as a `--recipe` parameter to AutoPkg
- **`REPO_LIST`** - A text file containing a list of any repos that need to be added in order to run the supplied recipes.
- **Any other keys** - Passed to AutoPkg as `--key KEY=VALUE` parameters
  - Examples: `replace_pkg`, `SELFSERVICE_POLICY_NAME`, etc.

### 4. Generate Dispatch Payload

Use the included script to base64-encode your configuration:

```bash
./create-dispatch-payload.sh --input autopkg-keys.json --output dispatch-payload.json
```

This creates a `dispatch-payload.json` file ready to POST to GitHub:

```json
{
  "event_type": "run-autopkg",
  "client_payload": {
    "data": "eyJKU1NfVVJMIjogImh0dHBzOi8veW91ci5qYW1mLmluc3RhbmNlLmNvbSIsIC4uLn0="
  }
}
```

#### Specifying the workflow platform

By default, the workflow will run with an `ubuntu-latest` runner. If the recipe(s) being run require macOS, specify the platform when creating the dispatch file. This is done with the `--platform` parameter. Currently, the only valid values for the platform parameter are:

- **ubuntu-latest**
- **macos-latest**

When you specify the platform, it is added to the dispatch file as follows:

```bash
./create-dispatch-payload.sh --input autopkg-keys.json --output dispatch-payload.json --platform macos-latest
```

This creates a `dispatch-payload.json` file ready to POST to GitHub:

```json
{
  "event_type": "run-autopkg",
  "client_payload": {
    "runner": "macos-latest",
    "data": "eyJKU1NfVVJMIjogImh0dHBzOi8veW91ci5qYW1mLmluc3RhbmNlLmNvbSIsIC4uLn0="
  }
}
```


### 5. Trigger the Workflow

Run the same file with the `--dispatch` option, also supplying your Personal Access Token:

```bash
./create-dispatch-payload.sh --input autopkg-keys.json --output dispatch-payload.json --dispatch --token github_pat_1122334455667788990
```

Remember to specify the platform if not `ubuntu-latest`.

**Response Codes:**

- `204 No Content` - Success! Workflow triggered
- `404 Not Found` - Token lacks permissions or repo not found
- `422 Unprocessable Entity` - Invalid payload format

### 6. Monitor the Run

Check your GitHub Actions tab to see the workflow execution and results.

## Workflow Behavior

- **Repository Dispatch**: Uses credentials and recipes from the JSON payload
- **Manual/Push Triggers**: Falls back to GitHub Secrets and the `recipe-list.txt` file

## Integration Example

For websites or external systems:

```javascript
// Generate base64-encoded JSON
const config = {
  JSS_URL: "https://your.jamf.instance.com",
  JSS_API_USER: "apiuser",
  JSS_API_PW: "password",
  GH_TOKEN: "ghp_token",
  RECIPE_1: "Firefox.jamf",
  RECIPE_2: "Chrome.jamf"
};

const base64Data = Buffer.from(JSON.stringify(config)).toString('base64');

// Trigger dispatch
const response = await fetch('https://api.github.com/repos/OWNER/REPO/dispatches', {
  method: 'POST',
  headers: {
    'Accept': 'application/vnd.github+json',
    'Authorization': `Bearer ${GITHUB_PAT}`,
    'X-GitHub-Api-Version': '2022-11-28'
  },
  body: JSON.stringify({
    event_type: 'run-autopkg',
    client_payload: {
      data: base64Data
    }
  })
});
```

## Security Considerations

- Never commit `autopkg-keys.json` or `dispatch-payload.json` to version control
- Store GitHub PATs securely (environment variables, secrets managers)
- Use fine-grained tokens with minimal repository access
- Rotate tokens regularly
- Set appropriate token expiration dates
- For production, consider using GitHub Apps instead of PATs

## Requirements

- GitHub Actions enabled on the repository
- AutoPkg recipe repositories (configured in setup scripts)
- JamfUploader processors
- Jamf Pro API access with appropriate permissions

## License

See LICENSE file for details.
