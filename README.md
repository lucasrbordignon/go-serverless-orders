# Go Serverless Orders

Projeto de estudo de arquitetura **serverless e event-driven** utilizando Go e serviços AWS.

A infraestrutura AWS é executada localmente utilizando **MiniStack**.

## Arquitetura

Estado atual:

```text
Client
  │
  │ POST /orders
  ▼
API Gateway
  │
  │ AWS_PROXY
  ▼
Lambda
create-order


SQS
order-processing
```

> Neste momento, a Lambda e o SQS já estão funcionando isoladamente. A integração `create-order → SQS` será implementada na próxima etapa.

Arquitetura planejada:

```text
Client
  │
  ▼
API Gateway
  │
  ▼
Lambda
create-order
  │
  ▼
SQS
order-processing
  │
  ▼
Lambda
process-order
  │
  ▼
SNS
order-events
  │
  ├── Consumer
  ├── Consumer
  └── Consumer
```

## Tecnologias

- Go
- AWS Lambda
- Amazon API Gateway
- Amazon SQS
- Amazon SNS
- MiniStack
- Docker
- AWS CLI

## Estrutura

```text
.
├── cmd/
│   └── create-order/
│       ├── main.go
│       └── main_test.go
├── .gitignore
├── go.mod
├── go.sum
└── README.md
```

## Pré-requisitos

É necessário ter instalado:

- Go
- Docker
- AWS CLI
- ZIP

Verifique:

```bash
go version
docker --version
aws --version
zip --version
```

## Configuração local

### 1. Instalar dependências

```bash
go mod download
```

### 2. Executar testes

```bash
go test ./... -v
```

### 3. Iniciar o MiniStack

```bash
docker run -d \
  --name ministack \
  -p 4566:4566 \
  ministackorg/ministack
```

Se o container já existir:

```bash
docker start ministack
```

### 4. Configurar AWS CLI

O ambiente local utiliza credenciais fictícias:

```bash
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1
```

Verifique a comunicação:

```bash
aws \
  --region us-east-1 \
  --endpoint-url=http://localhost:4566 \
  lambda list-functions
```

## Lambda `create-order`

### Build

A Lambda utiliza o runtime `provided.al2023`.

```bash
GOOS=linux \
GOARCH=amd64 \
CGO_ENABLED=0 \
go build -o bootstrap ./cmd/create-order
```

### Empacotamento

```bash
zip function.zip bootstrap
```

### Criar a Lambda

```bash
aws \
  --region us-east-1 \
  --endpoint-url=http://localhost:4566 \
  lambda create-function \
  --function-name create-order \
  --runtime provided.al2023 \
  --handler bootstrap \
  --zip-file fileb://function.zip \
  --role arn:aws:iam::000000000000:role/lambda-role
```

## API Gateway

Criamos uma REST API que expõe:

```http
POST /orders
```

Fluxo:

```text
POST /orders
      │
      ▼
 API Gateway
      │
      │ AWS_PROXY
      ▼
 create-order
```

### Testar a API

Após criar o deployment no stage `dev`:

```bash
curl -X POST \
  "http://localhost:4566/restapis/$API_ID/dev/_user_request_/orders" \
  -H "Content-Type: application/json" \
  -d '{
    "customer_id": "customer-123",
    "amount": 150.50
  }'
```

Resposta atual:

```json
{
  "message": "order received"
}
```

## SQS

A fila responsável pelo processamento assíncrono dos pedidos é:

```text
order-processing
```

### Criar a fila

```bash
aws \
  --region us-east-1 \
  --endpoint-url=http://localhost:4566 \
  sqs create-queue \
  --queue-name order-processing
```

### Obter a URL da fila

```bash
QUEUE_URL=$(aws \
  --region us-east-1 \
  --endpoint-url=http://localhost:4566 \
  sqs get-queue-url \
  --queue-name order-processing \
  --query 'QueueUrl' \
  --output text)
```

### Enviar uma mensagem manualmente

```bash
aws \
  --region us-east-1 \
  --endpoint-url=http://localhost:4566 \
  sqs send-message \
  --queue-url "$QUEUE_URL" \
  --message-body '{"customer_id":"customer-123","amount":150.50}'
```

### Consumir uma mensagem manualmente

```bash
aws \
  --region us-east-1 \
  --endpoint-url=http://localhost:4566 \
  sqs receive-message \
  --queue-url "$QUEUE_URL"
```

Essa etapa valida o SQS isoladamente antes da integração com a Lambda.

## Fluxo de desenvolvimento

Depois de modificar a Lambda:

```bash
go test ./... -v
```

Compile novamente:

```bash
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 \
go build -o bootstrap ./cmd/create-order
```

Atualize o ZIP:

```bash
zip -f function.zip bootstrap
```

## Arquivos locais

Não devem ser versionados:

```gitignore
create-order
bootstrap
function.zip
event.json
response.json
```

## Status

- [x] Inicialização do projeto Go
- [x] Handler Lambda
- [x] Testes unitários
- [x] Parsing do request
- [x] Validação do request
- [x] MiniStack
- [x] Build para AWS Lambda
- [x] Execução da Lambda no MiniStack
- [x] API Gateway
- [x] `POST /orders`
- [x] Integração API Gateway → Lambda
- [x] SQS `order-processing`
- [x] Envio e consumo manual de mensagens SQS
- [ ] Integração Lambda → SQS
- [ ] Lambda `process-order`
- [ ] Integração SQS → Lambda
- [ ] SNS
- [ ] Fan-out
- [ ] DLQ
- [ ] Idempotência
- [ ] Observabilidade
