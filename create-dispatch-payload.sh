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
  --dispatch     Perform the dispatch
  --help, -h     Show this help message
"
    exit 0
}

# Defaults
OUTPUT_FILE="dispatch-payload.json"
EVENT_TYPE="run-autopkg"

# Parse arguments
while test $# -gt 0
do
    case "$1" in
        -h|--help)
            usage
            ;;
        -i|--input)
            shift
            INPUT_FILE="$1"
            ;;
        -o|--output)
            shift
            OUTPUT_FILE="$1"
            ;;
        --event-type)
            shift
            EVENT_TYPE="$1"
            ;;
        --dispatch)
            dispatch="true"
            ;;
        --token)
            shift
            TOKEN="$1"
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

# Base64 encode the input file
ENCODED=$(base64 -i "$INPUT_FILE")

# Create the dispatch payload
cat > "$OUTPUT_FILE" <<EOF
{
  "event_type": "$EVENT_TYPE",
  "client_payload": {
    "data": "$ENCODED"
  }
}
EOF

if [[ $? -eq 0 ]]; then
    echo "Dispatch payload created: $OUTPUT_FILE"
    if [[ "$dispatch" == "true" ]]; then
        # extract GitHub token from file
        if [[ -z "$TOKEN" ]]; then
            echo "ERROR: no token supplied"
        fi

        response_code=$(curl -s -o /dev/null -w "%{http_code}" -L -X POST \
            -H "Accept: application/vnd.github+json" \
            -H "Authorization: Bearer $TOKEN" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            https://api.github.com/repos/grahampugh/autopkg-linux-runner/dispatches \
            -d @"$OUTPUT_FILE")
        
        echo "Dispatch response code: $response_code" # DEBUG
        
        if [[ "$response_code" == "204" ]]; then
            echo "Workflow dispatch successful"
        else
            echo "ERROR: Workflow dispatch failed with code: $response_code"
            exit 1
        fi
    else
        echo ""
        echo "To trigger the workflow, run:"
        echo "curl -L -X POST \\"
        echo "  -H \"Accept: application/vnd.github+json\" \\"
        echo "  -H \"Authorization: Bearer <YOUR_TOKEN>\" \\"
        echo "  -H \"X-GitHub-Api-Version: 2022-11-28\" \\"
        echo "  https://api.github.com/repos/grahampugh/autopkg-linux-runner/dispatches \\"
        echo "  -d @$OUTPUT_FILE"
    fi
else
    echo "ERROR: Failed to create dispatch payload."
    exit 1
fi
