#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=== n8n テスト仕様書作成環境 ==="
echo ""

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    echo "Error: Docker is not installed."
    echo "Please install Docker: https://docs.docker.com/get-docker/"
    exit 1
fi

if ! command -v docker compose &> /dev/null && ! command -v docker-compose &> /dev/null; then
    echo "Error: Docker Compose is not installed."
    exit 1
fi

# Create necessary directories
mkdir -p "$PROJECT_ROOT/n8n/workflows"
mkdir -p "$PROJECT_ROOT/n8n/output"
mkdir -p "$PROJECT_ROOT/n8n/templates"

echo "Starting n8n..."
cd "$PROJECT_ROOT"

# Use docker compose (v2) or docker-compose (v1)
if command -v docker compose &> /dev/null; then
    docker compose up -d n8n
else
    docker-compose up -d n8n
fi

echo ""
echo "n8n is starting up..."
echo ""
echo "  Web UI: http://localhost:5678"
echo ""
echo "Wait a few seconds for n8n to be ready, then:"
echo ""
echo "  1. Open http://localhost:5678 in your browser"
echo "  2. Create an account (first time only)"
echo "  3. Import workflows from n8n/workflows/ directory"
echo ""
echo "To import a workflow:"
echo "  - In n8n UI: Menu > Import from File"
echo "  - Select a JSON file from n8n/workflows/"
echo ""
echo "Available workflows:"
echo "  - test-spec-generator.json          : Webhook API for test spec generation"
echo "  - test-spec-from-csv.json           : Generate test specs from CSV data"
echo "  - test-spec-batch-from-spreadsheet.json : Manual trigger batch generation"
echo ""
echo "To stop n8n:"
echo "  docker compose down"
