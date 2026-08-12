package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/sns"
)

type OrderMessage struct {
	CustomerID string  `json:"customer_id"`
	Amount     float64 `json:"amount"`
}

type OrderProcessedEvent struct {
	EventType  string  `json:"event_type"`
	CustomerID string  `json:"customer_id"`
	Amount     float64 `json:"amount"`
}

type EventPublisher interface {
	Publish(
		ctx context.Context,
		params *sns.PublishInput,
		optFns ...func(*sns.Options),
	) (*sns.PublishOutput, error)
}

var snsClient EventPublisher

func init() {
	cfg, err := config.LoadDefaultConfig(context.Background())
	if err != nil {
		return
	}

	snsClient = sns.NewFromConfig(cfg, func(o *sns.Options) {
		if endpoint := os.Getenv("AWS_ENDPOINT_URL"); endpoint != "" {
			o.BaseEndpoint = aws.String(endpoint)
		}
	})
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

		eventBody, err := json.Marshal(OrderProcessedEvent{
			EventType:  "order.processed",
			CustomerID: order.CustomerID,
			Amount:     order.Amount,
		})
		if err != nil {
			return fmt.Errorf("failed to serialize event: %w", err)
		}

		_, err = snsClient.Publish(ctx, &sns.PublishInput{
			TopicArn: aws.String(os.Getenv("ORDER_EVENTS_TOPIC_ARN")),
			Message:  aws.String(string(eventBody)),
		})
		if err != nil {
			return fmt.Errorf("failed to publish event: %w", err)
		}
	}

	return nil
}

func main() {
	lambda.Start(handler)
}
