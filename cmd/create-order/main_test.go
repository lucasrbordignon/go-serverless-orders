package main

import (
	"context"
	"testing"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
)

type mockQueue struct{}

func (m *mockQueue) SendMessage(
	ctx context.Context,
	params *sqs.SendMessageInput,
	optFns ...func(*sqs.Options),
) (*sqs.SendMessageOutput, error) {
	return &sqs.SendMessageOutput{}, nil
}

func TestHandler(t *testing.T) {
	sqsClient = &mockQueue{}
	t.Setenv("ORDER_QUEUE_URL", "http://localhost/test-queue")

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

	if response.StatusCode != 202 {
		t.Fatalf("expected status code 202, got %d", response.StatusCode)
	}

	expectedBody := `{"message":"order queued"}`

	if response.Body != expectedBody {
		t.Fatalf("expected body %s, got %s", expectedBody, response.Body)
	}
}
