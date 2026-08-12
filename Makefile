.PHONY: setup test build clean reset

setup:
	./scripts/setup-local.sh

test:
	go test ./... -v

build:
	GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o bootstrap ./cmd/create-order
	zip -q function-create-order.zip bootstrap
	rm bootstrap

	GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o bootstrap ./cmd/process-order
	zip -q function-process-order.zip bootstrap
	rm bootstrap

clean:
	rm -f bootstrap
	rm -f function-create-order.zip
	rm -f function-process-order.zip
	rm -f event.json
	rm -f response.json

reset:
	-docker stop ministack
	-docker rm ministack