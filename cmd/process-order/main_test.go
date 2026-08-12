package main

import (
	"context"
	"testing"

	"github.com/aws/aws-lambda-go/events"
)

func TestHandler(t *testing.T) {
	event := events.SQSEvent{
		Records: []events.SQSMessage{
			{
				Body: `{
					"customer_id": "customer-123",
					"amount": 150.50
				}`,
			},
		},
	}

	err := handler(context.Background(), event)

	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
}

func TestHandlerInvalidMessage(t *testing.T) {
	event := events.SQSEvent{
		Records: []events.SQSMessage{
			{
				Body: `{invalid-json}`,
			},
		},
	}

	err := handler(context.Background(), event)

	if err == nil {
		t.Fatal("expected an error")
	}
}
