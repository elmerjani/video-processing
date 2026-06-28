FROM public.ecr.aws/docker/library/golang:1.25-alpine AS build

WORKDIR /src

COPY go.mod go.sum* ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/worker .

FROM public.ecr.aws/docker/library/alpine:3.20

RUN apk add --no-cache ca-certificates ffmpeg

WORKDIR /app
COPY --from=build /out/worker /app/worker

USER 65532:65532

ENTRYPOINT ["/app/worker"]
