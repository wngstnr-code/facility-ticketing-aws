#!/usr/bin/env bash
# Deploy Facility Ticketing (DynamoDB + Lambda + API Gateway HTTP API)
# Dijalankan di AWS CloudShell pada akun AWS Academy Learner Lab (us-east-1).
# Aman dijalankan ulang: resource yang sudah ada dipakai lagi / diperbarui.
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
PREFIX="${PREFIX:-facility-tickets}"
TABLE="${PREFIX}"
FUNC="${PREFIX}-api"
API_NAME="${PREFIX}-http-api"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export AWS_DEFAULT_REGION="$REGION"

say() { printf '\n==> %s\n' "$*"; }

say "Akun & identitas"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws sts get-caller-identity --output table

# Learner Lab tidak mengizinkan membuat IAM role baru -> pakai LabRole bawaan.
ROLE_ARN=$(aws iam get-role --role-name LabRole --query Role.Arn --output text)
echo "Execution role: $ROLE_ARN"

say "1/4 DynamoDB table: $TABLE"
if aws dynamodb describe-table --table-name "$TABLE" >/dev/null 2>&1; then
  echo "Tabel sudah ada."
else
  aws dynamodb create-table \
    --table-name "$TABLE" \
    --attribute-definitions AttributeName=ticket_id,AttributeType=S \
    --key-schema AttributeName=ticket_id,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --tags Key=project,Value=facility-ticketing >/dev/null
  aws dynamodb wait table-exists --table-name "$TABLE"
  echo "Tabel dibuat (on-demand)."
fi

say "2/4 Lambda function: $FUNC"
BUILD="$ROOT/build"; mkdir -p "$BUILD"
( cd "$ROOT/src/tickets" && zip -q -r "$BUILD/function.zip" app.py )
if aws lambda get-function --function-name "$FUNC" >/dev/null 2>&1; then
  aws lambda update-function-code --function-name "$FUNC" \
    --zip-file "fileb://$BUILD/function.zip" >/dev/null
  aws lambda wait function-updated --function-name "$FUNC"
  echo "Kode function diperbarui."
else
  aws lambda create-function \
    --function-name "$FUNC" \
    --runtime python3.12 \
    --handler app.lambda_handler \
    --role "$ROLE_ARN" \
    --zip-file "fileb://$BUILD/function.zip" \
    --timeout 10 --memory-size 128 \
    --environment "Variables={TABLE_NAME=$TABLE}" \
    --tags project=facility-ticketing >/dev/null
  aws lambda wait function-active-v2 --function-name "$FUNC"
  echo "Function dibuat (python3.12, 128 MB)."
fi
FUNC_ARN=$(aws lambda get-function --function-name "$FUNC" --query Configuration.FunctionArn --output text)

say "3/4 API Gateway HTTP API: $API_NAME"
API_ID=$(aws apigatewayv2 get-apis --query "Items[?Name=='$API_NAME'].ApiId | [0]" --output text)
if [ "$API_ID" = "None" ] || [ -z "$API_ID" ]; then
  API_ID=$(aws apigatewayv2 create-api --name "$API_NAME" --protocol-type HTTP \
    --cors-configuration "AllowOrigins=*,AllowMethods=GET,POST,PUT,DELETE,AllowHeaders=content-type" \
    --tags project=facility-ticketing --query ApiId --output text)
  echo "API dibuat: $API_ID"
else
  echo "API sudah ada: $API_ID"
fi

INTEGRATION_ID=$(aws apigatewayv2 get-integrations --api-id "$API_ID" \
  --query "Items[?IntegrationUri=='$FUNC_ARN'].IntegrationId | [0]" --output text)
if [ "$INTEGRATION_ID" = "None" ] || [ -z "$INTEGRATION_ID" ]; then
  INTEGRATION_ID=$(aws apigatewayv2 create-integration --api-id "$API_ID" \
    --integration-type AWS_PROXY --integration-uri "$FUNC_ARN" \
    --payload-format-version 2.0 --query IntegrationId --output text)
fi

for ROUTE in "POST /tickets" "GET /tickets" "GET /tickets/{id}" "PUT /tickets/{id}" "DELETE /tickets/{id}" "GET /health"; do
  EXISTS=$(aws apigatewayv2 get-routes --api-id "$API_ID" \
    --query "Items[?RouteKey=='$ROUTE'].RouteId | [0]" --output text)
  if [ "$EXISTS" = "None" ] || [ -z "$EXISTS" ]; then
    aws apigatewayv2 create-route --api-id "$API_ID" --route-key "$ROUTE" \
      --target "integrations/$INTEGRATION_ID" >/dev/null
    echo "  + route $ROUTE"
  else
    echo "  = route $ROUTE (sudah ada)"
  fi
done

if ! aws apigatewayv2 get-stage --api-id "$API_ID" --stage-name '$default' >/dev/null 2>&1; then
  aws apigatewayv2 create-stage --api-id "$API_ID" --stage-name '$default' --auto-deploy \
    --default-route-settings "ThrottlingBurstLimit=20,ThrottlingRateLimit=10" >/dev/null
fi

say "4/4 Izin API Gateway -> Lambda (resource-based policy)"
aws lambda add-permission --function-name "$FUNC" \
  --statement-id apigw-invoke --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:$REGION:$ACCOUNT_ID:$API_ID/*/*" >/dev/null 2>&1 \
  && echo "Izin ditambahkan." || echo "Izin sudah ada."

API_URL="https://$API_ID.execute-api.$REGION.amazonaws.com"
cat > "$ROOT/outputs.env" <<EOF
API_URL=$API_URL
API_ID=$API_ID
TABLE=$TABLE
FUNC=$FUNC
EOF

say "Selesai"
echo "API_URL = $API_URL"
echo "Tes cepat: curl -s $API_URL/health"
echo "Tes CRUD : ./scripts/smoke-test.sh"
