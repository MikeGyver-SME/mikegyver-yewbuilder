# YewBuilder builder server — Docker image (optional; Windows run-server.ps1 is the default).
# Builds with Rust + trunk + Python, then serves POST /build on :8080.
FROM rust:1.82-slim-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends python3 curl pkg-config libssl-dev \
    && rm -rf /var/lib/apt/lists/* \
    && rustup target add wasm32-unknown-unknown \
    && cargo install trunk --locked

WORKDIR /app
COPY server.py .
EXPOSE 8080
CMD ["python3", "server.py", "8080"]
