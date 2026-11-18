#!/bin/sh
# Run this once before the talk, while you still have good internet.
# It downloads every base image and dependency, so the live demos work on bad Wi-Fi.
set -eu
cd "$(dirname "$0")"

docker pull alpine:3.24
docker pull maven:3.9-eclipse-temurin-25
docker pull eclipse-temurin:25-jre

# Demos 1 and 2 are NOT built here on purpose: they only need alpine, and building
# them live shows a real first build followed by a fully CACHED second build.
# Demo 3 is built now, because its first build downloads all Maven dependencies.
docker build -t demo-app:localdev --target localdev 03-multistage
docker build -t demo-app:final 03-multistage
docker compose -f 03-multistage/compose.yaml build

trivy image --download-db-only
trivy image --download-java-db-only

echo "Ready. Images:"
docker images --filter reference="demo-*"
