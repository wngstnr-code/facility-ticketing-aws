#!/usr/bin/env bash
# Hapus semua resource proyek agar budget Learner Lab tidak terpakai.
set -uo pipefail
export AWS_DEFAULT_REGION="${AWS_REGION:-us-east-1}"
PREFIX="${PREFIX:-facility-tickets}"

API_ID=$(aws apigatewayv2 get-apis --query "Items[?Name=='${PREFIX}-http-api'].ApiId | [0]" --output text)
[ "$API_ID" != "None" ] && aws apigatewayv2 delete-api --api-id "$API_ID" >/dev/null && echo "API $API_ID dihapus"
aws lambda delete-function --function-name "${PREFIX}-api" >/dev/null 2>&1 && echo "Lambda dihapus"
aws logs delete-log-group --log-group-name "/aws/lambda/${PREFIX}-api" 2>/dev/null && echo "Log group dihapus"
aws dynamodb delete-table --table-name "$PREFIX" >/dev/null 2>&1 && echo "Tabel DynamoDB dihapus"
rm -f "$(cd "$(dirname "$0")/.." && pwd)/outputs.env"
echo "Cleanup selesai."
