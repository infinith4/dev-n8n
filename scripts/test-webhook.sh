#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
N8N_URL="${N8N_URL:-http://localhost:5678}"

echo "=== テスト仕様書生成 Webhook テスト ==="
echo ""

# Test 1: JSON input
echo "--- Test 1: JSON入力でテスト仕様書生成 ---"
echo ""
echo "Request:"
echo "  POST ${N8N_URL}/webhook-test/generate-test-spec"
echo ""

curl -s -X POST "${N8N_URL}/webhook-test/generate-test-spec" \
  -H "Content-Type: application/json" \
  -d @"${PROJECT_ROOT}/n8n/templates/sample-request.json" | jq '.' 2>/dev/null || echo "(n8n is not running or workflow is not active)"

echo ""
echo ""

# Test 2: CSV input
echo "--- Test 2: CSV入力でテスト仕様書生成 ---"
echo ""
echo "Request:"
echo "  POST ${N8N_URL}/webhook-test/generate-test-spec-from-csv"
echo ""

curl -s -X POST "${N8N_URL}/webhook-test/generate-test-spec-from-csv" \
  -H "Content-Type: application/json" \
  -d @"${PROJECT_ROOT}/n8n/templates/sample-csv-request.json" | jq '.' 2>/dev/null || echo "(n8n is not running or workflow is not active)"

echo ""
echo "=== Done ==="
