# syntax=docker/dockerfile:1
FROM rust:1.95-alpine AS build
RUN apk add --no-cache musl-dev
ARG APP_VERSION=dev
WORKDIR /src
COPY Cargo.toml Cargo.lock ./
COPY src ./src
RUN APP_VERSION=${APP_VERSION} cargo build --release --locked

FROM scratch
COPY --from=build /src/target/release/delivery-app /app
USER 10001:10001
EXPOSE 8080
ENTRYPOINT ["/app"]
