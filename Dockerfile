FROM alpine:latest

WORKDIR /app

RUN apk add --no-cache bash jq curl

COPY src/* .
RUN chmod +x *.sh

CMD [ "/app/run.sh" ]
