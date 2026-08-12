package main

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
)

type SNSMessageEnvelope struct {
	Message string `json:"Message"`
}

type OrderProcessedEvent struct {
	EventType  string  `json:"event_type"`
	CustomerID string  `json:"customer_id"`
	Amount     float64 `json:"amount"`
}

func handler(ctx context.Context, event events.SQSEvent) error {
	for _, record := range event.Records {
		var envelope SNSMessageEnvelope

		if err := json.Unmarshal([]byte(record.Body), &envelope); err != nil {
			return fmt.Errorf("failed to parse SNS envelope: %w", err)
		}

		var orderEvent OrderProcessedEvent

		if err := json.Unmarshal([]byte(envelope.Message), &orderEvent); err != nil {
			return fmt.Errorf("failed to parse order event: %w", err)
		}

		fmt.Printf(
			"notification received: event=%s customer=%s amount=%.2f\n",
			orderEvent.EventType,
			orderEvent.CustomerID,
			orderEvent.Amount,
		)
	}

	return nil
}

func main() {
	lambda.Start(handler)
}
