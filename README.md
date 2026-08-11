# Go Serverless Orders

Projeto de estudo de arquitetura serverless e orientada a eventos utilizando **Go** e serviços AWS.

A infraestrutura AWS é executada localmente utilizando **MiniStack**.

## Arquitetura

Neste momento, o projeto possui apenas a primeira Lambda:

```text
Request
   │
   ▼
Lambda
create-order
```

A arquitetura será evoluída gradualmente para:

```text
Client
  │
  ▼
API Gateway
  │
  ▼
Lambda
  │
  ▼
SQS
  │
  ▼
Lambda
  │
  ▼
SNS
  │
  ├── Consumer
  ├── Consumer
  └── Consumer
```

## Tecnologias

- Go
- AWS Lambda
- API Gateway
- SQS
- SNS
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

## 1. Instalar dependências

Na raiz do projeto:

```bash
go mod download
```

## 2. Executar os testes

Execute todos os testes:

```bash
go test ./... -v
```

## 3. Compilar

Para verificar se o projeto compila:

```bash
go build ./cmd/create-order
```

Isso gera o executável:

```text
create-order
```

Esse executável é apenas um artefato local e não deve ser versionado.

## 4. Iniciar o MiniStack

Execute:

```bash
docker run -d \
  --name ministack \
  -p 4566:4566 \
  ministackorg/ministack
```

Verifique:

```bash
docker ps
```

Se o container já existir e estiver parado:

```bash
docker start ministack
```

## 5. Configurar AWS CLI para desenvolvimento local

Configure credenciais locais:

```bash
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1
```

Essas credenciais são utilizadas somente para acessar o ambiente AWS local.

Para verificar a comunicação:

```bash
aws \
  --endpoint-url=http://localhost:4566 \
  lambda list-functions
```

## 6. Gerar o binário da Lambda

A Lambda utiliza o runtime:

```text
provided.al2023
```

Compile o projeto para Linux:

```bash
GOOS=linux \
GOARCH=amd64 \
CGO_ENABLED=0 \
go build -o bootstrap ./cmd/create-order
```

Verifique o binário:

```bash
file bootstrap
```

O executável deve ser um ELF Linux `x86-64`.

## 7. Criar o pacote da Lambda

Compacte o `bootstrap`:

```bash
zip function.zip bootstrap
```

O arquivo gerado será:

```text
function.zip
```

Os artefatos abaixo não devem ser versionados:

```gitignore
create-order
bootstrap
function.zip
```

## 8. Criar a Lambda no MiniStack

Com o MiniStack rodando:

```bash
aws \
  --endpoint-url=http://localhost:4566 \
  lambda create-function \
  --function-name create-order \
  --runtime provided.al2023 \
  --handler bootstrap \
  --zip-file fileb://function.zip \
  --role arn:aws:iam::000000000000:role/lambda-role
```

Confira as funções disponíveis:

```bash
aws \
  --endpoint-url=http://localhost:4566 \
  lambda list-functions
```

A função `create-order` deverá aparecer na resposta.

## Desenvolvimento

Depois de modificar o código da Lambda, execute novamente:

```bash
go test ./... -v
```

E gere novamente os artefatos:

```bash
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 \
go build -o bootstrap ./cmd/create-order

zip -f function.zip bootstrap
```

## Status

- [x] Projeto Go
- [x] Handler Lambda
- [x] Testes unitários
- [x] Parsing do request
- [x] Validação inicial
- [x] MiniStack
- [x] Build para AWS Lambda
- [ ] Executar Lambda localmente
- [ ] API Gateway
- [ ] SQS
- [ ] Processamento assíncrono
- [ ] SNS
- [ ] DLQ
- [ ] Idempotência
- [ ] Observabilidade
