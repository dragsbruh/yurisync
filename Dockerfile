FROM alpine:latest

WORKDIR /src

RUN apk add --no-cache bash jq curl

COPY sync.sh .

CMD [ "/src/sync.sh" ]
