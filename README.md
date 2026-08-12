# Go Serverless Orders

Projeto de estudo de arquitetura **serverless e event-driven** utilizando **Go** e serviços AWS.

O objetivo é construir gradualmente uma arquitetura distribuída utilizando API Gateway, AWS Lambda, SQS, SNS, DLQ, idempotência e observabilidade.

Para desenvolvimento local, os serviços AWS são emulados utilizando **MiniStack** e Docker.

---

## Arquitetura atual

O fluxo abaixo está funcional:

```text id="dmkvsa"
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
7. O Event Source Mapping identifica mensagens disponíveis.
8. A Lambda `process-order` é invocada.
9. O pedido é processado assincronamente.

A API não precisa aguardar o processamento completo do pedido.

---

# Arquitetura planejada

```text id="8b5ju6"
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
  │     Lambda
  │
  ├── SQS audit
  │       │
  │       ▼
  │     Lambda
  │
  └── outros consumidores
```

Posteriormente serão adicionados:

```text id="34nb5v"
SQS
 │
 ├── Retry
 └── DLQ

Consumers
 │
 └── Idempotência

AWS
 │
 ├── Logs
 ├── Métricas
 └── Observabilidade
```

---

# Tecnologias

- Go
- AWS Lambda
- Amazon API Gateway
- Amazon SQS
- Amazon SNS
- AWS SDK for Go v2
- MiniStack
- Docker
- AWS CLI
- Make

---

# Estrutura

```text id="w3hn69"
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
│   └── setup-local.sh
│
├── Makefile
├── .gitignore
├── go.mod
├── go.sum
└── README.md
```

---

# Executando o projeto

## Pré-requisitos

É necessário ter instalado:

- Go
- Docker
- AWS CLI
- ZIP
- Make

Verifique:

```bash id="mzwzvy"
go version
docker --version
aws --version
zip --version
make --version
```

---

## Instalar dependências

```bash id="g6t5nz"
go mod download
```

---

## Executar testes

```bash id="dlfnlq"
make test
```

Equivalente a:

```bash id="ir7rqv"
go test ./... -v
```

---

# Ambiente AWS local

O projeto utiliza MiniStack para emular os serviços AWS localmente.

A infraestrutura não precisa ser criada manualmente.

Execute:

```bash id="7ebc57"
make setup
```

Esse comando:

```text id="xlfu80"
make setup
     │
     ▼
scripts/setup-local.sh
     │
     ├── Docker network
     ├── MiniStack
     ├── Build das Lambdas
     ├── SQS
     ├── Lambdas
     ├── Event Source Mapping
     ├── API Gateway
     └── Deployment
```

Ao final, será exibido o endpoint da API:

```text id="82zbco"
============================================
 Local environment ready
============================================

API ID:
xxxxxxxx

Endpoint:
http://localhost:4566/restapis/xxxxxxxx/dev/_user_request_/orders
```

---

# Docker network

As Lambdas são executadas em containers.

O ambiente utiliza uma rede Docker compartilhada:

```text id="vnvh0a"
ministack-net
```

Arquitetura local:

```text id="6otzgb"
Docker
│
└── ministack-net
      │
      ├── ministack
      │     │
      │     ├── API Gateway
      │     ├── SQS
      │     └── outros serviços AWS
      │
      ├── Lambda create-order
      │
      └── Lambda process-order
```

Do host, o MiniStack é acessado através de:

```text id="i6cwwj"
http://localhost:4566
```

Dentro dos containers Lambda:

```text id="obx4n8"
http://ministack:4566
```

`localhost` dentro de um container aponta para o próprio container, portanto as Lambdas utilizam o hostname `ministack` para acessar os serviços AWS locais.

---

# Makefile

O projeto possui comandos para simplificar o desenvolvimento.

## Setup

Cria todo o ambiente local:

```bash id="5k7r2d"
make setup
```

## Testes

```bash id="of7dnp"
make test
```

## Build

Compila e empacota as duas Lambdas:

```bash id="mz4gpo"
make build
```

São gerados:

```text id="nsgx25"
function-create-order.zip
function-process-order.zip
```

## Limpeza

Remove artefatos locais:

```bash id="63l1n4"
make clean
```

## Reset

Remove o container atual do MiniStack:

```bash id="4fh3no"
make reset
```

Para recriar todo o ambiente:

```bash id="7jd8qm"
make reset
make setup
```

---

# Lambda `create-order`

Responsável pela entrada de novos pedidos.

Recebe:

```json id="e03cml"
{
  "customer_id": "customer-123",
  "amount": 150.5
}
```

Fluxo:

```text id="dxv9an"
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

A Lambda utiliza o AWS SDK for Go v2 para publicar no SQS.

### Variáveis

```text id="ggkex5"
ORDER_QUEUE_URL=http://ministack:4566/000000000000/order-processing
AWS_ENDPOINT_URL=http://ministack:4566
```

---

# API Gateway

Endpoint:

```http id="ypz85l"
POST /orders
```

Teste:

```bash id="z5s37u"
curl -X POST \
  "http://localhost:4566/restapis/{API_ID}/dev/_user_request_/orders" \
  -H "Content-Type: application/json" \
  -d '{
    "customer_id": "customer-777",
    "amount": 450.00
  }'
```

Resposta:

```json id="l1c7i5"
{
  "message": "order queued"
}
```

Status:

```text id="o5sgrm"
202 Accepted
```

O `202` indica que o pedido foi aceito, mas será processado assincronamente.

---

# SQS

Fila:

```text id="0bfm7x"
order-processing
```

Responsabilidade:

```text id="j2wscu"
create-order
     │
     ▼
order-processing
     │
     ▼
process-order
```

O SQS funciona como buffer entre produção e processamento.

Isso desacopla as Lambdas:

```text id="n1hkb3"
create-order

não precisa conhecer

process-order
```

A primeira Lambda apenas publica uma mensagem.

---

# Lambda `process-order`

Consome mensagens da fila `order-processing`.

O handler recebe:

```go id="v6s65s"
events.SQSEvent
```

Uma invocação pode possuir vários registros:

```text id="lxhig3"
SQSEvent
 │
 ├── Record
 ├── Record
 └── Record
```

Cada `record.Body` contém o pedido.

Atualmente:

```text id="9byx1q"
processing order:
customer=customer-777
amount=450.00
```

---

# Event Source Mapping

O Event Source Mapping conecta:

```text id="sdjnsl"
SQS
order-processing
      │
      ▼
Event Source Mapping
      │
      ▼
Lambda
process-order
```

Atualmente:

```text id="3p9i3s"
BatchSize = 1
```

Isso facilita visualizar cada processamento individualmente.

Posteriormente podemos testar processamento em batch.

---

# Testes

Os handlers possuem testes unitários.

Execute:

```bash id="hflc40"
make test
```

Atualmente são testados:

- parsing do request;
- validação;
- handler HTTP;
- publicação através da abstração de Queue;
- eventos SQS;
- mensagens inválidas.

Para evitar dependência da infraestrutura nos testes, o acesso ao SQS é abstraído:

```text id="0zwt0l"
                  Queue
                    ▲
           ┌────────┴────────┐
           │                 │
       sqs.Client        mockQueue
           │                 │
       runtime             testes
```

---

# Build

As Lambdas utilizam:

```text id="3xthvt"
GOOS=linux
GOARCH=amd64
CGO_ENABLED=0
```

Isso gera binários Linux compatíveis com o runtime utilizado pela Lambda.

Execute:

```bash id="h02ox6"
make build
```

Os executáveis são empacotados em arquivos ZIP contendo:

```text id="z8wjqk"
bootstrap
```

que é o entrypoint esperado pelo runtime `provided.al2023`.

---

# Setup automatizado

O script:

```text id="g7ftve"
scripts/setup-local.sh
```

é responsável por provisionar o ambiente local.

Atualmente ele cria:

```text id="j7mz3m"
Docker network
      ↓
MiniStack
      ↓
SQS order-processing
      ↓
Lambda create-order
      ↓
Lambda process-order
      ↓
Event Source Mapping
      ↓
API Gateway
      ↓
Stage dev
```

Isso torna o ambiente reproduzível.

Em vez de executar manualmente dezenas de comandos AWS:

```bash id="stnh21"
make setup
```

---

# Fluxo completo atual

```text id="4c6j72"
                     HTTP

Client
  │
  │ POST /orders
  ▼
API Gateway
  │
  ▼
create-order
  │
  │ SendMessage
  ▼

               ASYNC

SQS order-processing
  │
  │ Event Source Mapping
  ▼
process-order
  │
  ▼
processing
```

---

# Estado do projeto

- [x] Inicialização do projeto Go
- [x] Handler `create-order`
- [x] Testes unitários
- [x] Parsing do request
- [x] Validação
- [x] MiniStack
- [x] Docker network
- [x] AWS SDK for Go v2
- [x] API Gateway
- [x] `POST /orders`
- [x] API Gateway → Lambda
- [x] SQS `order-processing`
- [x] Lambda → SQS
- [x] Lambda `process-order`
- [x] Event Source Mapping
- [x] SQS → Lambda
- [x] Fluxo assíncrono funcional
- [x] Build automatizado
- [x] Setup local automatizado
- [x] Makefile
- [ ] Setup idempotente
- [ ] SNS `order-events`
- [ ] `process-order` → SNS
- [ ] Fan-out
- [ ] Consumers adicionais
- [ ] Retry
- [ ] Dead Letter Queue
- [ ] Idempotência
- [ ] Observabilidade
- [ ] Testes end-to-end automatizados

---

# Próxima etapa

O próximo componente será o SNS:

```text id="92b3ki"
process-order
      │
      │ Publish
      ▼
SNS
order-events
```

Com isso poderemos distribuir um evento para múltiplos consumidores:

```text id="pgx83q"
                  order.processed
                        │
                        ▼
                 SNS order-events
                        │
              ┌─────────┼─────────┐
              │         │         │
              ▼         ▼         ▼
          Notification Audit   Analytics
```

Essa etapa introduzirá o padrão **publish/subscribe** e **fan-out** na arquitetura.
