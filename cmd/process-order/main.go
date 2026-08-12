package main

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
)

type OrderMessage struct {
	CustomerID string  `json:"customer_id"`
	Amount     float64 `json:"amount"`
}

func handler(ctx context.Context, event events.SQSEvent) error {
	for _, record := range event.Records {
		var order OrderMessage

		if err := json.Unmarshal([]byte(record.Body), &order); err != nil {
			return fmt.Errorf("failed to parse order: %w", err)
		}

		fmt.Printf(
			"processing order: customer=%s amount=%.2f\n",
			order.CustomerID,
			order.Amount,
		)
	}

	return nil
}

func main() {
	lambda.Start(handler)
}
