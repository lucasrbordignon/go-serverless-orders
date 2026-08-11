package main

import (
	"context"
	"testing"

	"github.com/aws/aws-lambda-go/events"
)

func TestHandler(t *testing.T) {
	request := events.APIGatewayProxyRequest{
		Body: `{
			"customer_id": "123",
			"amount": 100.5
		}`,
	}

	response, err := handler(context.Background(), request)

	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}

	if response.StatusCode != 200 {
		t.Fatalf("expected status code 200, got %d", response.StatusCode)
	}

	expectedBody := `{"message":"order received"}`

	if response.Body != expectedBody {
		t.Fatalf("expected body %s, got %s", expectedBody, response.Body)
	}
}
