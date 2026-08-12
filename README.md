# Go Serverless Orders

Projeto de estudo de arquitetura **serverless, assíncrona e event-driven** utilizando **Go** e serviços AWS.

O projeto explora, de forma incremental, conceitos como:

- API Gateway;
- AWS Lambda;
- filas;
- processamento assíncrono;
- pub/sub;
- fan-out;
- retry;
- Dead Letter Queue;
- idempotência;
- observabilidade;
- infraestrutura local reproduzível.

Para desenvolvimento local, os serviços AWS são emulados com **MiniStack** e Docker.

---

# Arquitetura atual

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
  │
  │ Publish order.processed
  ▼
SNS
order-events
  │
  ├─────────────────────────────┐
  │                             │
  ▼                             ▼
SQS                           SQS
notification-queue            audit-queue
  │                             │
  ▼                             ▼
Lambda                        Lambda
notification-consumer         audit-consumer
```

A fila principal também possui uma Dead Letter Queue:

```text
order-processing
       │
       ▼
 process-order
       │
       ├── sucesso
       │
       └── falha
             │
             ▼
           retry
             │
             ▼
           retry
             │
             ▼
 order-processing-dlq
```

---

# Fluxo da aplicação

## 1. Entrada HTTP

O cliente envia:

```http
POST /orders
```

Exemplo:

```json
{
  "customer_id": "customer-123",
  "amount": 150.5
}
```

---

## 2. API Gateway

O API Gateway recebe a requisição e utiliza uma integração `AWS_PROXY` para encaminhá-la à Lambda:

```text
create-order
```

---

## 3. Lambda `create-order`

A Lambda:

1. faz o parsing do JSON;
2. valida os dados;
3. publica o pedido na fila `order-processing`;
4. responde `202 Accepted`.

```text
HTTP
 │
 ▼
create-order
 │
 ▼
SQS
```

Resposta:

```json
{
  "message": "order queued"
}
```

O `202` representa que a requisição foi aceita para processamento assíncrono.

---

## 4. SQS `order-processing`

A fila desacopla a entrada HTTP do processamento do pedido.

```text
create-order
      │
      ▼
order-processing
      │
      ▼
process-order
```

A Lambda `create-order` não precisa conhecer diretamente o consumer.

Ela apenas publica a mensagem.

---

## 5. Event Source Mapping

Um Event Source Mapping conecta:

```text
SQS order-processing
        │
        ▼
Lambda process-order
```

Atualmente:

```text
BatchSize = 1
```

Uma mensagem disponível na fila provoca uma invocação da Lambda consumidora.

---

## 6. Lambda `process-order`

A Lambda recebe:

```go
events.SQSEvent
```

Ela:

1. lê a mensagem;
2. realiza o processamento;
3. publica um evento `order.processed`;
4. envia esse evento para o SNS.

```text
order-processing
       │
       ▼
 process-order
       │
       ▼
 order.processed
       │
       ▼
      SNS
```

---

# SNS

O tópico utilizado é:

```text
order-events
```

Depois que um pedido é processado:

```text
process-order
      │
      │ Publish
      ▼
SNS order-events
```

O SNS permite que múltiplos consumidores recebam o mesmo evento sem que `process-order` precise conhecê-los.

---

# Fan-out

O tópico `order-events` possui duas subscriptions:

```text
                   order.processed
                          │
                          ▼
                  SNS order-events
                    /           \
                   /             \
                  ▼               ▼
       notification-queue      audit-queue
```

Um único evento publicado gera mensagens independentes para as duas filas.

Isso permite que cada fluxo seja processado isoladamente.

---

# Notification Consumer

Fluxo:

```text
SNS
 │
 ▼
notification-queue
 │
 ▼
notification-consumer
```

A Lambda recebe a mensagem através do SQS.

Como a mensagem foi originalmente publicada pelo SNS, o body possui um envelope.

```text
SQS record
    │
    ▼
SNS envelope
    │
    ▼
Message
    │
    ▼
OrderProcessedEvent
```

Exemplo de log:

```text
notification received:
event=order.processed
customer=customer-123
amount=150.50
```

---

# Audit Consumer

Fluxo:

```text
SNS
 │
 ▼
audit-queue
 │
 ▼
audit-consumer
```

O consumer transforma o evento em um log estruturado de auditoria.

Exemplo:

```json
{
  "type": "audit",
  "event_type": "order.processed",
  "customer_id": "customer-123",
  "amount": 150.5
}
```

Os consumers são independentes.

Uma falha na notificação não precisa impedir o fluxo de auditoria e vice-versa.

---

# Retry e Dead Letter Queue

A fila principal possui:

```text
order-processing-dlq
```

A configuração de redrive utiliza:

```text
maxReceiveCount = 3
```

Fluxo:

```text
order-processing
       │
       ▼
 process-order
       │
       ├── sucesso
       │      │
       │      └── mensagem removida
       │
       └── falha
              │
              ▼
            retry
              │
              ▼
            retry
              │
              ▼
    order-processing-dlq
```

O retry não é implementado com um loop manual dentro do código Go.

O processamento falha retornando erro, permitindo que a infraestrutura de mensageria faça novas tentativas.

Após atingir o limite configurado, a mensagem é direcionada para a DLQ.

---

# Arquitetura completa atual

```text
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
  ├──────────────────────────► order-processing-dlq
  │                               após falhas
  │
  ▼
process-order
  │
  │ Publish
  ▼
SNS order-events
  │
  ├──────────────────────────────┐
  │                              │
  ▼                              ▼
notification-queue             audit-queue
  │                              │
  ▼                              ▼
notification-consumer          audit-consumer
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
- Bash

Planejado:

- Redis para idempotência;
- observabilidade;
- testes end-to-end adicionais.

---

# Estrutura

```text
.
├── cmd/
│   ├── create-order/
│   │   ├── main.go
│   │   └── main_test.go
│   │
│   ├── process-order/
│   │   ├── main.go
│   │   └── main_test.go
│   │
│   ├── notification-consumer/
│   │   ├── main.go
│   │   └── main_test.go
│   │
│   └── audit-consumer/
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

# Pré-requisitos

É necessário possuir:

- Go;
- Docker;
- AWS CLI;
- ZIP;
- Make;
- Python 3.

Verifique:

```bash
go version
docker --version
aws --version
zip --version
make --version
python3 --version
```

---

# Instalação

```bash
go mod download
```

---

# Testes

Execute:

```bash
make test
```

Equivalente a:

```bash
go test ./... -v
```

São testados atualmente:

- parsing do request HTTP;
- validações;
- publicação na abstração de Queue;
- processamento de eventos SQS;
- eventos SNS encapsulados em SQS;
- notification consumer;
- audit consumer;
- mensagens inválidas;
- falhas de processamento.

Dependências AWS são abstraídas quando necessário para permitir utilização de mocks.

---

# Ambiente local

O ambiente completo pode ser criado com:

```bash
make setup
```

O script:

```text
scripts/setup-local.sh
```

provisiona:

```text
Docker network
      │
      ▼
MiniStack
      │
      ├── API Gateway
      │
      ├── SNS
      │
      ├── SQS
      │
      └── Lambdas
```

Além dos vínculos entre os serviços.

---

# Docker Network

O projeto utiliza:

```text
ministack-net
```

Arquitetura:

```text
Docker
 │
 └── ministack-net
       │
       ├── ministack
       │
       ├── create-order Lambda
       │
       ├── process-order Lambda
       │
       ├── notification-consumer Lambda
       │
       └── audit-consumer Lambda
```

No host:

```text
http://localhost:4566
```

Dentro das Lambdas:

```text
http://ministack:4566
```

`localhost` dentro de um container representa o próprio container, portanto os runtimes Lambda utilizam o hostname `ministack`.

---

# Recursos locais

## SQS

```text
order-processing
order-processing-dlq
notification-queue
audit-queue
```

## SNS

```text
order-events
```

## Lambdas

```text
create-order
process-order
notification-consumer
audit-consumer
```

## API

```http
POST /orders
```

---

# Makefile

## Criar ambiente

```bash
make setup
```

## Testes unitários

```bash
make test
```

## Build

```bash
make build
```

## Limpeza

```bash
make clean
```

## Remover ambiente

```bash
make reset
```

## Recriar ambiente

```bash
make restart
```

## Testar API

```bash
make test-api
```

O target procura automaticamente o API Gateway atual e realiza um `POST /orders`.

Isso evita depender de um `API_ID` manual no shell.

## Logs

```bash
make logs
```

---

# Build

Os binários são compilados utilizando:

```text
GOOS=linux
GOARCH=amd64
CGO_ENABLED=0
```

Os artefatos Lambda são:

```text
function-create-order.zip
function-process-order.zip
function-notification-consumer.zip
function-audit-consumer.zip
```

Cada ZIP contém um executável:

```text
bootstrap
```

compatível com:

```text
provided.al2023
```

---

# Setup automatizado

O `setup-local.sh` atualmente executa aproximadamente:

```text
create Docker network
        │
        ▼
start MiniStack
        │
        ▼
build Lambdas
        │
        ▼
create order-processing-dlq
        │
        ▼
create order-processing
        │
        ├── configure RedrivePolicy
        │
        ▼
create notification-queue
        │
        ▼
create audit-queue
        │
        ▼
create SNS order-events
        │
        ├── subscribe notification-queue
        └── subscribe audit-queue
        │
        ▼
deploy Lambdas
        │
        ▼
create Event Source Mappings
        │
        ▼
create API Gateway
        │
        ▼
deploy stage dev
```

---

# Estado do projeto

- [x] Projeto Go
- [x] Lambda `create-order`
- [x] API Gateway
- [x] `POST /orders`
- [x] Validação
- [x] `202 Accepted`
- [x] AWS SDK for Go v2
- [x] SQS `order-processing`
- [x] Lambda → SQS
- [x] Lambda `process-order`
- [x] SQS → Lambda
- [x] SNS `order-events`
- [x] `process-order` → SNS
- [x] Fan-out
- [x] `notification-queue`
- [x] `notification-consumer`
- [x] `audit-queue`
- [x] `audit-consumer`
- [x] Retry
- [x] Dead Letter Queue
- [x] `maxReceiveCount`
- [x] Docker network
- [x] Setup automatizado
- [x] Build automatizado
- [x] Makefile
- [x] `make test-api`
- [x] Testes unitários
- [ ] Identificador único `order_id`
- [ ] Idempotência
- [ ] Redis
- [ ] Observabilidade
- [ ] Testes end-to-end automatizados
- [ ] Hardening final da infraestrutura

---

# Próxima etapa

O próximo problema a ser tratado é duplicidade de processamento.

Sistemas baseados em filas devem considerar a possibilidade de uma mesma operação ser recebida novamente.

Para isso, o pedido terá um identificador único:

```text
order_id
```

O identificador será criado em:

```text
create-order
```

e propagado através de toda a arquitetura:

```text
create-order
     │
     │ order_id
     ▼
SQS
     │
     ▼
process-order
     │
     │ order_id
     ▼
SNS
   /   \
  ▼     ▼
notification
audit
```

Depois disso será adicionada uma camada de idempotência com Redis.

Arquitetura planejada:

```text
                  order-processing
                         │
                         ▼
                   process-order
                         │
                         ▼
                       Redis
                         │
                  ┌──────┴──────┐
                  │             │
             chave nova     chave existe
                  │             │
                  ▼             ▼
              processa        ignora
                  │
                  ▼
             SNS Publish
```

A chave será baseada no `order_id`, permitindo identificar mensagens já processadas.

Depois da idempotência, a última grande etapa será observabilidade.
