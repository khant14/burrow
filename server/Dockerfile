# Build from the repo root: docker build -f server/Dockerfile -t burrow-server .
FROM rust:1-slim AS build
WORKDIR /src
COPY . .
RUN cargo build --release -p burrow-server
