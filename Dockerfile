FROM golang:alpine AS builder

WORKDIR /app

COPY src/server.go .
RUN go build -o server server.go

FROM alpine:latest

WORKDIR /app

RUN apk add --no-cache bash jq curl

COPY src/*.sh ./
COPY --from=builder /app/server .
RUN chmod +x ./*.sh ./server

CMD [ "/app/run.sh" ]
