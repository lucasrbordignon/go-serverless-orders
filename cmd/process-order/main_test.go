package main

import (
	"context"
	"testing"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-sdk-go-v2/service/sns"
)

type mockPublisher struct{}

func (m *mockPublisher) Publish(
	ctx context.Context,
	params *sns.PublishInput,
	optFns ...func(*sns.Options),
) (*sns.PublishOutput, error) {
	return &sns.PublishOutput{}, nil
}

func TestHandler(t *testing.T) {
	snsClient = &mockPublisher{}

	t.Setenv(
		"ORDER_EVENTS_TOPIC_ARN",
		"arn:aws:sns:us-east-1:000000000000:order-events",
	)

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
