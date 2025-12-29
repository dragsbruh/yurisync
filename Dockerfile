FROM golang:alpine AS builder

WORKDIR /app

COPY server.go .
RUN go build -o server server.go

FROM alpine:latest

WORKDIR /app

RUN apk add --no-cache bash jq curl

COPY sync.sh run.sh ./
COPY --from=builder /app/server .
RUN chmod +x sync.sh run.sh server

CMD [ "/app/run.sh" ]
