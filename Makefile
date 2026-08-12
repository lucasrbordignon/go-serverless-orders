.PHONY: setup test test-api build clean reset restart logs

AWS_ENV = AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1
ENDPOINT = http://localhost:4566

setup:
	./scripts/setup-local.sh

test:
	go test ./... -v

test-api:
	@API_ID=$$($(AWS_ENV) aws --region us-east-1 --endpoint-url=$(ENDPOINT) apigateway get-rest-apis --query "items[?name=='go-serverless-orders'].id | [0]" --output text); \
	if [ -z "$$API_ID" ] || [ "$$API_ID" = "None" ]; then \
		echo "API Gateway not found"; \
		exit 1; \
	fi; \
	echo "Testing API: $$API_ID"; \
	curl -i -X POST "$(ENDPOINT)/restapis/$$API_ID/dev/_user_request_/orders" \
		-H "Content-Type: application/json" \
		-d '{"customer_id":"customer-test","amount":199.90}'

build:
	GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o bootstrap ./cmd/create-order
	zip -q function-create-order.zip bootstrap
	rm bootstrap

	GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o bootstrap ./cmd/process-order
	zip -q function-process-order.zip bootstrap
	rm bootstrap

	GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o bootstrap ./cmd/notification-consumer
	zip -q function-notification-consumer.zip bootstrap
	rm bootstrap

	GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o bootstrap ./cmd/audit-consumer
	zip -q function-audit-consumer.zip bootstrap
	rm bootstrap

clean:
	rm -f bootstrap
	rm -f create-order
	rm -f process-order
	rm -f notification-consumer
	rm -f audit-consumer
	rm -f function-create-order.zip
	rm -f function-process-order.zip
	rm -f function-notification-consumer.zip
	rm -f function-audit-consumer.zip
	rm -f event.json
	rm -f response.json

reset:
	-docker stop ministack
	-docker rm ministack

restart: reset setup

logs:
	docker logs ministack --tail 100 -f