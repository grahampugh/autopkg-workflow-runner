#!/usr/bin/env bash

# create-dispatch-payload.sh
# Creates a GitHub repository dispatch payload from a JSON file
# by Graham Pugh

usage() {
    echo "
Usage: ./create-dispatch-payload.sh --input <input.json> --output <output.json>

Options:
  --input, -i    Path to the input JSON file to encode
  --output, -o   Path to the output dispatch payload file (default: dispatch-payload.json)
  --event-type   Event type for the dispatch (default: run-autopkg)
  --branch       Branch to run workflow on (triggers workflow_dispatch instead of repository_dispatch)
  --workflow     Workflow file name (required with --branch, e.g., autopkg-run.yml)
  --dispatch     Perform the dispatch
  --help, -h     Show this help message
"
    exit 0
}

# Defaults
OUTPUT_FILE="dispatch-payload.json"
EVENT_TYPE="run-autopkg"

# Parse arguments
while test $# -gt 0; do
    case "$1" in
    -h | --help)
        usage
        ;;
    -i | --input)
        shift
        INPUT_FILE="$1"
        ;;
    -o | --output)
        shift
        OUTPUT_FILE="$1"
        ;;
    --event-type)
        shift
        EVENT_TYPE="$1"
        ;;
    --branch)
        shift
        BRANCH="$1"
        ;;
    --workflow)
        shift
        WORKFLOW="$1"
        ;;
    --dispatch)
        dispatch="true"
        ;;
    --token)
        shift
        TOKEN="$1"
        ;;
    --platform | --runner)
        shift
        PLATFORM="$1"
        ;;
    *)
        echo "Unknown parameter: $1"
        usage
        ;;
    esac
    shift
done

# Validate input file
if [[ -z "$INPUT_FILE" ]]; then
    echo "ERROR: Input file is required."
    usage
fi

if [[ ! -f "$INPUT_FILE" ]]; then
    echo "ERROR: Input file '$INPUT_FILE' not found."
    exit 1
fi

# Validate JSON
if ! jq empty "$INPUT_FILE" 2>/dev/null; then
    echo "ERROR: Input file '$INPUT_FILE' is not valid JSON."
    exit 1
fi

# Validate platform
if [[ "$PLATFORM" != "ubuntu-latest" && "$PLATFORM" != "macos-latest" ]]; then
    PLATFORM="ubuntu-latest"
fi

# Validate workflow file when branch is specified
if [[ -n "$BRANCH" && -z "$WORKFLOW" ]]; then
    echo "ERROR: --workflow is required when using --branch"
    exit 1
fi

# Base64 encode the input file
ENCODED=$(base64 -i "$INPUT_FILE")

# Create the dispatch payload
if [[ -n "$BRANCH" ]]; then
    # Use workflow_dispatch format
    cat >"$OUTPUT_FILE" <<EOF
{
  "ref": "$BRANCH",
  "inputs": {
    "runner": "$PLATFORM",
    "data": "$ENCODED"
  }
}
EOF
else
    # Use repository_dispatch format
    cat >"$OUTPUT_FILE" <<EOF
{
  "event_type": "$EVENT_TYPE",
  "client_payload": {
    "runner": "$PLATFORM",
    "data": "$ENCODED"
  }
}
EOF
fi

if [[ $? -eq 0 ]]; then
    echo "Dispatch payload created: $OUTPUT_FILE"
    if [[ "$dispatch" == "true" ]]; then
        # extract GitHub token from file
        if [[ -z "$TOKEN" ]]; then
            echo "ERROR: no token supplied"
        fi

        # Use different endpoint based on dispatch type
        if [[ -n "$BRANCH" ]]; then
            # workflow_dispatch endpoint
            API_URL="https://api.github.com/repos/jamf/msp-services-autopkg-runner/actions/workflows/$WORKFLOW/dispatches"
            DISPATCH_TYPE="workflow_dispatch"
        else
            # repository_dispatch endpoint
            API_URL="https://api.github.com/repos/jamf/msp-services-autopkg-runner/dispatches"
            DISPATCH_TYPE="repository_dispatch"
        fi

        response_code=$(curl -s -o /dev/null -w "%{http_code}" -L -X POST \
            -H "Accept: application/vnd.github+json" \
            -H "Authorization: Bearer $TOKEN" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            "$API_URL" \
            -d @"$OUTPUT_FILE")

        echo "Dispatch response code: $response_code" # DEBUG

        if [[ "$response_code" == "204" ]]; then
            echo "$DISPATCH_TYPE successful"
        else
            echo "ERROR: $DISPATCH_TYPE failed with code: $response_code"
            exit 1
        fi
    else
        echo ""
        echo "To trigger the workflow, run:"
        if [[ -n "$BRANCH" ]]; then
            echo "curl -L -X POST \\"
            echo "  -H \"Accept: application/vnd.github+json\" \\"
            echo "  -H \"Authorization: Bearer <YOUR_TOKEN>\" \\"
            echo "  -H \"X-GitHub-Api-Version: 2022-11-28\" \\"
            echo "  https://api.github.com/repos/jamf/msp-services-autopkg-runner/actions/workflows/$WORKFLOW/dispatches \\"
            echo "  -d @$OUTPUT_FILE"
        else
            echo "curl -L -X POST \\"
            echo "  -H \"Accept: application/vnd.github+json\" \\"
            echo "  -H \"Authorization: Bearer <YOUR_TOKEN>\" \\"
            echo "  -H \"X-GitHub-Api-Version: 2022-11-28\" \\"
            echo "  https://api.github.com/repos/jamf/msp-services-autopkg-runner/dispatches \\"
            echo "  -d @$OUTPUT_FILE"
        fi
    fi
else
    echo "ERROR: Failed to create dispatch payload."
    exit 1
fi
