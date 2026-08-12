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
  docker network create "$NETWORK" >/dev/null
fi

if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
  echo "==> Creating MiniStack container"

  docker run -d \
    --name "$CONTAINER" \
    --network "$NETWORK" \
    -e DOCKER_NETWORK="$NETWORK" \
    -p 4566:4566 \
    ministackorg/ministack >/dev/null
else
  echo "==> MiniStack container already exists"

  if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER")" != "true" ]; then
    echo "==> Starting MiniStack"
    docker start "$CONTAINER" >/dev/null
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

echo "==> Building notification-consumer"

GOOS=linux GOARCH=amd64 CGO_ENABLED=0 \
  go build -o bootstrap ./cmd/notification-consumer

zip -q function-notification-consumer.zip bootstrap
rm bootstrap

echo "==> Building audit-consumer"

GOOS=linux GOARCH=amd64 CGO_ENABLED=0 \
  go build -o bootstrap ./cmd/audit-consumer

zip -q function-audit-consumer.zip bootstrap
rm bootstrap

# ---------------------------------------------------------
# SQS
# ---------------------------------------------------------

echo "==> Creating order-processing queue"

QUEUE_URL=$(aws \
  --region "$REGION" \
  --endpoint-url="$ENDPOINT" \
  sqs create-queue \
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

echo "==> Creating notification queue"

NOTIFICATION_QUEUE_URL=$(aws \
  --region "$REGION" \
  --endpoint-url="$ENDPOINT" \
  sqs create-queue \
  --queue-name notification-queue \
  --query 'QueueUrl' \
  --output text)

NOTIFICATION_QUEUE_ARN=$(aws \
  --region "$REGION" \
  --endpoint-url="$ENDPOINT" \
  sqs get-queue-attributes \
  --queue-url "$NOTIFICATION_QUEUE_URL" \
  --attribute-names QueueArn \
  --query 'Attributes.QueueArn' \
  --output text)

echo "==> Creating audit queue"

AUDIT_QUEUE_URL=$(aws \
  --region "$REGION" \
  --endpoint-url="$ENDPOINT" \
  sqs create-queue \
  --queue-name audit-queue \
  --query 'QueueUrl' \
  --output text)

AUDIT_QUEUE_ARN=$(aws \
  --region "$REGION" \
  --endpoint-url="$ENDPOINT" \
  sqs get-queue-attributes \
  --queue-url "$AUDIT_QUEUE_URL" \
  --attribute-names QueueArn \
  --query 'Attributes.QueueArn' \
  --output text)

# ---------------------------------------------------------
# SNS
# ---------------------------------------------------------

echo "==> Creating order-events SNS topic"

TOPIC_ARN=$(aws \
  --region "$REGION" \
  --endpoint-url="$ENDPOINT" \
  sns create-topic \
  --name order-events \
  --query 'TopicArn' \
  --output text)

echo "==> Subscribing audit queue to SNS"

aws \
  --region "$REGION" \
  --endpoint-url="$ENDPOINT" \
  sns subscribe \
  --topic-arn "$TOPIC_ARN" \
  --protocol sqs \
  --notification-endpoint "$AUDIT_QUEUE_ARN" \
  >/dev/null

echo "==> Subscribing notification queue to SNS"

aws \
  --region "$REGION" \
  --endpoint-url="$ENDPOINT" \
  sns subscribe \
  --topic-arn "$TOPIC_ARN" \
  --protocol sqs \
  --notification-endpoint "$NOTIFICATION_QUEUE_ARN" \
  >/dev/null

# ---------------------------------------------------------
# Lambda create-order
# ---------------------------------------------------------

echo "==> Deploying create-order Lambda"

if aws \
  --region "$REGION" \
  --endpoint-url="$ENDPOINT" \
  lambda get-function \
  --function-name create-order \
  >/dev/null 2>&1; then

  aws \
    --region "$REGION" \
    --endpoint-url="$ENDPOINT" \
    lambda update-function-code \
    --function-name create-order \
    --zip-file fileb://function-create-order.zip \
    >/dev/null
else
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
fi

aws \
  --region "$REGION" \
  --endpoint-url="$ENDPOINT" \
  lambda update-function-configuration \
  --function-name create-order \
  --environment "Variables={ORDER_QUEUE_URL=$INTERNAL_QUEUE_URL,AWS_ENDPOINT_URL=$INTERNAL_ENDPOINT}" \
  >/dev/null

# ---------------------------------------------------------
# Lambda process-order
# ---------------------------------------------------------

echo "==> Deploying process-order Lambda"

if aws \
  --region "$REGION" \
  --endpoint-url="$ENDPOINT" \
  lambda get-function \
  --function-name process-order \
  >/dev/null 2>&1; then

  aws \
    --region "$REGION" \
    --endpoint-url="$ENDPOINT" \
    lambda update-function-code \
    --function-name process-order \
    --zip-file fileb://function-process-order.zip \
    >/dev/null
else
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
fi

aws \
  --region "$REGION" \
  --endpoint-url="$ENDPOINT" \
  lambda update-function-configuration \
  --function-name process-order \
  --environment "Variables={ORDER_EVENTS_TOPIC_ARN=$TOPIC_ARN,AWS_ENDPOINT_URL=$INTERNAL_ENDPOINT}" \
  >/dev/null

# ---------------------------------------------------------
# Lambda notification-consumer
# ---------------------------------------------------------

echo "==> Deploying notification-consumer Lambda"

if aws \
  --region "$REGION" \
  --endpoint-url="$ENDPOINT" \
  lambda get-function \
  --function-name notification-consumer \
  >/dev/null 2>&1; then

  aws \
    --region "$REGION" \
    --endpoint-url="$ENDPOINT" \
    lambda update-function-code \
    --function-name notification-consumer \
    --zip-file fileb://function-notification-consumer.zip \
    >/dev/null
else
  aws \
    --region "$REGION" \
    --endpoint-url="$ENDPOINT" \
    lambda create-function \
    --function-name notification-consumer \
    --runtime provided.al2023 \
    --handler bootstrap \
    --zip-file fileb://function-notification-consumer.zip \
    --role arn:aws:iam::000000000000:role/lambda-role \
    >/dev/null
fi

# ---------------------------------------------------------
# Lambda audit-consumer
# ---------------------------------------------------------

echo "==> Deploying audit-consumer Lambda"

if aws \
  --region "$REGION" \
  --endpoint-url="$ENDPOINT" \
  lambda get-function \
  --function-name audit-consumer \
  >/dev/null 2>&1; then

  aws \
    --region "$REGION" \
    --endpoint-url="$ENDPOINT" \
    lambda update-function-code \
    --function-name audit-consumer \
    --zip-file fileb://function-audit-consumer.zip \
    >/dev/null
else
  aws \
    --region "$REGION" \
    --endpoint-url="$ENDPOINT" \
    lambda create-function \
    --function-name audit-consumer \
    --runtime provided.al2023 \
    --handler bootstrap \
    --zip-file fileb://function-audit-consumer.zip \
    --role arn:aws:iam::000000000000:role/lambda-role \
    >/dev/null
fi

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

echo "==> Connecting notification-queue to notification-consumer"

aws \
  --region "$REGION" \
  --endpoint-url="$ENDPOINT" \
  lambda create-event-source-mapping \
  --function-name notification-consumer \
  --event-source-arn "$NOTIFICATION_QUEUE_ARN" \
  --batch-size 1 \
  >/dev/null

echo "==> Connecting audit-queue to audit-consumer"

aws \
  --region "$REGION" \
  --endpoint-url="$ENDPOINT" \
  lambda create-event-source-mapping \
  --function-name audit-consumer \
  --event-source-arn "$AUDIT_QUEUE_ARN" \
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

# ---------------------------------------------------------
# Output
# ---------------------------------------------------------

API_URL="$ENDPOINT/restapis/$API_ID/dev/_user_request_/orders"

echo
echo "============================================"
echo " Local environment ready"
echo "============================================"
echo
echo "API ID:"
echo "$API_ID"
echo
echo "API URL:"
echo "$API_URL"
echo
echo "SQS:"
echo "$QUEUE_URL"
echo
echo "SNS:"
echo "$TOPIC_ARN"
echo
echo "Test:"
echo "curl -X POST \"$API_URL\" -H \"Content-Type: application/json\" -d '{\"customer_id\":\"customer-123\",\"amount\":150.50}'"
echo