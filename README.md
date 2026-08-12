# Go Serverless Orders

Projeto de estudo de arquitetura **serverless e event-driven** utilizando **Go** e serviços AWS.

O objetivo é construir gradualmente uma arquitetura distribuída utilizando API Gateway, AWS Lambda, SQS, SNS, DLQ, idempotência e observabilidade.

Para desenvolvimento local, os serviços AWS são emulados utilizando **MiniStack** e Docker.

## Arquitetura atual

Atualmente, o seguinte fluxo está funcional:

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
  │
  │ SendMessage
  ▼
SQS
order-processing
  │
  │ Event Source Mapping
  ▼
Lambda
process-order
```

### Fluxo

1. O cliente envia `POST /orders`.
2. O API Gateway encaminha a requisição para `create-order`.
3. A Lambda valida o payload.
4. A Lambda publica o pedido na fila `order-processing`.
5. A API responde `202 Accepted`.
6. O SQS mantém a mensagem até ela ser consumida.
7. O Event Source Mapping dispara `process-order`.
8. A Lambda processa a mensagem.

Essa arquitetura permite que a API não precise aguardar o processamento completo do pedido.

## Arquitetura planejada

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
  ├── SQS notification
  │       │
  │       ▼
  │    Lambda
  │
  ├── SQS audit
  │       │
  │       ▼
  │    Lambda
  │
  └── outros consumidores
```

Também serão adicionados:

```text
SQS
 │
 ├── retry
 │
 └── DLQ

Consumers
 │
 └── idempotência

AWS
 │
 └── observabilidade
```

## Tecnologias

- Go
- AWS Lambda
- Amazon API Gateway
- Amazon SQS
- Amazon SNS
- AWS SDK for Go v2
- MiniStack
- Docker
- AWS CLI

## Estrutura

```text
.
├── cmd/
│   ├── create-order/
│   │   ├── main.go
│   │   └── main_test.go
│   │
│   └── process-order/
│       ├── main.go
│       └── main_test.go
│
├── scripts/
│   └── # automação local será adicionada
│
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

## Instalação

Instale as dependências:

```bash
go mod download
```

Execute os testes:

```bash
go test ./... -v
```

## MiniStack

### Criar rede Docker

As Lambdas são executadas em containers.

Por isso, criamos uma rede compartilhada para permitir comunicação entre os containers das Lambdas e o MiniStack.

```bash
docker network create ministack-net
```

### Iniciar MiniStack

```bash
docker run -d \
  --name ministack \
  --network ministack-net \
  -e DOCKER_NETWORK=ministack-net \
  -p 4566:4566 \
  ministackorg/ministack
```

Se o container já existir:

```bash
docker start ministack
```

## AWS CLI

Configure credenciais locais:

```bash
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1
```

Essas credenciais são utilizadas somente no ambiente AWS local.

O endpoint do MiniStack acessível pela máquina host é:

```text
http://localhost:4566
```

Dentro dos containers Lambda, o MiniStack é acessado através de:

```text
http://ministack:4566
```

Isso ocorre porque `localhost` dentro de um container aponta para o próprio container.

## Lambda `create-order`

Responsável por receber e validar novos pedidos e publicá-los no SQS.

Entrada:

```json
{
  "customer_id": "customer-123",
  "amount": 150.5
}
```

Fluxo:

```text
APIGatewayProxyRequest
        │
        ▼
   JSON parsing
        │
        ▼
    Validation
        │
        ▼
   SQS SendMessage
        │
        ▼
   202 Accepted
```

### Variáveis de ambiente

```text
ORDER_QUEUE_URL=http://ministack:4566/000000000000/order-processing
AWS_ENDPOINT_URL=http://ministack:4566
```

## Build da `create-order`

```bash
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 \
go build -o bootstrap ./cmd/create-order
```

Empacote:

```bash
zip function.zip bootstrap
```

## API Gateway

A aplicação expõe:

```http
POST /orders
```

No ambiente local:

```text
http://localhost:4566/restapis/{API_ID}/dev/_user_request_/orders
```

Exemplo:

```bash
curl -X POST \
  "http://localhost:4566/restapis/$API_ID/dev/_user_request_/orders" \
  -H "Content-Type: application/json" \
  -d '{
    "customer_id": "customer-777",
    "amount": 450.00
  }'
```

Resposta:

```json
{
  "message": "order queued"
}
```

Status:

```text
202 Accepted
```

O `202` é utilizado porque a requisição foi aceita, mas o processamento ocorre de forma assíncrona.

## SQS

Fila:

```text
order-processing
```

Responsabilidade:

```text
create-order
     │
     ▼
order-processing
     │
     ▼
process-order
```

O SQS desacopla a criação do pedido do processamento.

A Lambda `create-order` não precisa saber quando ou como o pedido será processado.

## Lambda `process-order`

Responsável por consumir mensagens da fila `order-processing`.

Ela recebe:

```go
events.SQSEvent
```

Uma invocação pode conter uma ou mais mensagens:

```text
SQSEvent
 │
 ├── Record
 ├── Record
 └── Record
```

Cada `record.Body` contém o pedido publicado por `create-order`.

Atualmente o processamento registra:

```text
processing order: customer=customer-777 amount=450.00
```

## Event Source Mapping

O SQS não chama diretamente nosso código.

Existe um Event Source Mapping responsável por conectar:

```text
SQS
order-processing
      │
      │ Event Source Mapping
      ▼
Lambda
process-order
```

Atualmente utilizamos:

```text
BatchSize = 1
```

Isso facilita o estudo inicial do comportamento do processamento.

Posteriormente podemos trabalhar com batches maiores.

## Testes

Execute todos:

```bash
go test ./...
```

Com detalhes:

```bash
go test ./... -v
```

Temos testes para:

- handler HTTP;
- parsing do pedido;
- validação;
- publicação através de uma abstração de Queue;
- processamento de eventos SQS;
- mensagens SQS inválidas.

A comunicação com SQS é abstraída através de uma interface para permitir mocks nos testes.

```text
                 Queue
                   ▲
          ┌────────┴────────┐
          │                 │
      sqs.Client        mockQueue
          │                 │
      produção            testes
```

## Build das Lambdas

### create-order

```bash
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 \
go build -o bootstrap ./cmd/create-order

zip function.zip bootstrap
```

### process-order

```bash
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 \
go build -o bootstrap-process-order ./cmd/process-order

cp bootstrap-process-order bootstrap

zip function-process-order.zip bootstrap

rm bootstrap
```

## Arquivos locais

Os artefatos de build não devem ser versionados:

```gitignore
create-order
process-order

bootstrap
bootstrap-process-order

function.zip
function-process-order.zip

event.json
response.json
```

## Estado atual

- [x] Inicialização do projeto Go
- [x] Handler `create-order`
- [x] Testes unitários
- [x] Parsing do request
- [x] Validação do request
- [x] MiniStack
- [x] Docker network
- [x] Build para AWS Lambda
- [x] Execução da Lambda local
- [x] API Gateway
- [x] `POST /orders`
- [x] API Gateway → Lambda
- [x] SQS `order-processing`
- [x] AWS SDK for Go v2
- [x] Lambda `create-order` → SQS
- [x] Lambda `process-order`
- [x] Testes de eventos SQS
- [x] Event Source Mapping
- [x] SQS → Lambda `process-order`
- [x] Fluxo assíncrono ponta a ponta
- [ ] Automatização do ambiente local
- [ ] SNS `order-events`
- [ ] Lambda `process-order` → SNS
- [ ] Fan-out
- [ ] Consumers adicionais
- [ ] Retry
- [ ] Dead Letter Queue
- [ ] Idempotência
- [ ] Observabilidade
- [ ] Testes end-to-end

## Próximas etapas

O próximo estágio da arquitetura será:

```text
process-order
      │
      │ Publish
      ▼
SNS
order-events
```

O SNS permitirá distribuir um mesmo evento para diferentes consumidores:

```text
                 order.processed
                       │
                       ▼
                      SNS
                 ┌─────┼─────┐
                 ▼     ▼     ▼
               Email  Audit Analytics
```

Isso permitirá explorar **fan-out e arquitetura orientada a eventos** sem acoplar `process-order` aos consumidores finais.
