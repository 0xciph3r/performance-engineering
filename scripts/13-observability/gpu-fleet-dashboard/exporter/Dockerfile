FROM golang:1.26-alpine AS build
WORKDIR /src
COPY main.go .
ENV GO111MODULE=off
RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o /dcgm-sim .

FROM alpine:3.20
COPY --from=build /dcgm-sim /dcgm-sim
EXPOSE 9400
ENTRYPOINT ["/dcgm-sim"]
