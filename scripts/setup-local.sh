#!/usr/bin/env bash

set -euo pipefail

ENDPOINT="http://localhost:4566"
INTERNAL_ENDPOINT="http://ministack:4566"
REGION="us-east-1"
NETWORK="ministack-net"
CONTAINER="ministack"

export AWS_ACCESS_KEY_ID="test"
export AWS_SECRET_ACCESS_KEY="test"
export AWS_DEFAULT_REGION="$REGION"

echo "==> Setting up local environment"

# ---------------------------------------------------------
# Docker
# ---------------------------------------------------------

if ! docker network inspect "$NETWORK" >/dev/null 2>&1; then
  echo "==> Creating Docker network"
  docker network create "$NETWORK"
fi

if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
  echo "==> Creating MiniStack container"

  docker run -d \
    --name "$CONTAINER" \
    --network "$NETWORK" \
    -e DOCKER_NETWORK="$NETWORK" \
    -p 4566:4566 \
    ministackorg/ministack
else
  echo "==> MiniStack container already exists"

  if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER")" != "true" ]; then
    echo "==> Starting MiniStack"
    docker start "$CONTAINER"
  fi
fi

echo "==> Waiting for MiniStack"

until curl -s "$ENDPOINT" >/dev/null; do
  sleep 1
done

echo "==> MiniStack ready"

# ---------------------------------------------------------
# Build
# ---------------------------------------------------------

echo "==> Building create-order"

GOOS=linux GOARCH=amd64 CGO_ENABLED=0 \
  go build -o bootstrap ./cmd/create-order

zip -q function-create-order.zip bootstrap
rm bootstrap

echo "==> Building process-order"

GOOS=linux GOARCH=amd64 CGO_ENABLED=0 \
  go build -o bootstrap ./cmd/process-order

zip -q function-process-order.zip bootstrap
rm bootstrap

# ---------------------------------------------------------
# SQS
# ---------------------------------------------------------

echo "==> Creating order-processing queue"

aws \
  --region "$REGION" \
  --endpoint-url="$ENDPOINT" \
  sqs create-queue \
  --queue-name order-processing \
  >/dev/null

QUEUE_URL=$(aws \
  --region "$REGION" \
  --endpoint-url="$ENDPOINT" \
  sqs get-queue-url \
  --queue-name order-processing \
  --query 'QueueUrl' \
  --output text)

QUEUE_ARN=$(aws \
  --region "$REGION" \
  --endpoint-url="$ENDPOINT" \
  sqs get-queue-attributes \
  --queue-url "$QUEUE_URL" \
  --attribute-names QueueArn \
  --query 'Attributes.QueueArn' \
  --output text)

INTERNAL_QUEUE_URL="$INTERNAL_ENDPOINT/000000000000/order-processing"

# ---------------------------------------------------------
# Lambdas
# ---------------------------------------------------------

echo "==> Creating create-order Lambda"

aws \
  --region "$REGION" \
  --endpoint-url="$ENDPOINT" \
  lambda create-function \
  --function-name create-order \
  --runtime provided.al2023 \
  --handler bootstrap \
  --zip-file fileb://function-create-order.zip \
  --role arn:aws:iam::000000000000:role/lambda-role \
  >/dev/null

aws \
  --region "$REGION" \
  --endpoint-url="$ENDPOINT" \
  lambda update-function-configuration \
  --function-name create-order \
  --environment "Variables={ORDER_QUEUE_URL=$INTERNAL_QUEUE_URL,AWS_ENDPOINT_URL=$INTERNAL_ENDPOINT}" \
  >/dev/null

echo "==> Creating process-order Lambda"

aws \
  --region "$REGION" \
  --endpoint-url="$ENDPOINT" \
  lambda create-function \
  --function-name process-order \
  --runtime provided.al2023 \
  --handler bootstrap \
  --zip-file fileb://function-process-order.zip \
  --role arn:aws:iam::000000000000:role/lambda-role \
  >/dev/null

# ---------------------------------------------------------
# SQS -> Lambda
# ---------------------------------------------------------

echo "==> Connecting SQS to process-order"

aws \
  --region "$REGION" \
  --endpoint-url="$ENDPOINT" \
  lambda create-event-source-mapping \
  --function-name process-order \
  --event-source-arn "$QUEUE_ARN" \
  --batch-size 1 \
  >/dev/null

# ---------------------------------------------------------
# API Gateway
# ---------------------------------------------------------

echo "==> Creating API Gateway"

API_ID=$(aws \
  --region "$REGION" \
  --endpoint-url="$ENDPOINT" \
  apigateway create-rest-api \
  --name go-serverless-orders \
  --query id \
  --output text)

ROOT_ID=$(aws \
  --region "$REGION" \
  --endpoint-url="$ENDPOINT" \
  apigateway get-resources \
  --rest-api-id "$API_ID" \
  --query 'items[?path==`/`].id' \
  --output text)

ORDERS_RESOURCE_ID=$(aws \
  --region "$REGION" \
  --endpoint-url="$ENDPOINT" \
  apigateway create-resource \
  --rest-api-id "$API_ID" \
  --parent-id "$ROOT_ID" \
  --path-part orders \
  --query id \
  --output text)

aws \
  --region "$REGION" \
  --endpoint-url="$ENDPOINT" \
  apigateway put-method \
  --rest-api-id "$API_ID" \
  --resource-id "$ORDERS_RESOURCE_ID" \
  --http-method POST \
  --authorization-type NONE \
  >/dev/null

LAMBDA_ARN=$(aws \
  --region "$REGION" \
  --endpoint-url="$ENDPOINT" \
  lambda get-function \
  --function-name create-order \
  --query 'Configuration.FunctionArn' \
  --output text)

aws \
  --region "$REGION" \
  --endpoint-url="$ENDPOINT" \
  apigateway put-integration \
  --rest-api-id "$API_ID" \
  --resource-id "$ORDERS_RESOURCE_ID" \
  --http-method POST \
  --type AWS_PROXY \
  --integration-http-method POST \
  --uri "arn:aws:apigateway:$REGION:lambda:path/2015-03-31/functions/$LAMBDA_ARN/invocations" \
  >/dev/null

aws \
  --region "$REGION" \
  --endpoint-url="$ENDPOINT" \
  apigateway create-deployment \
  --rest-api-id "$API_ID" \
  --stage-name dev \
  >/dev/null

echo
echo "============================================"
echo " Local environment ready"
echo "============================================"
echo
echo "API ID:"
echo "$API_ID"
echo
echo "Endpoint:"
echo "$ENDPOINT/restapis/$API_ID/dev/_user_request_/orders"
echo