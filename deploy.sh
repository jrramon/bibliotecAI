#!/bin/bash
# BibliotecAI Production Deployment Script
# Usage: ./deploy.sh

set -e

COMPOSE_FILE="docker-compose.production.yml"
APP_DIR="/opt/biblio"

cd "$APP_DIR"

echo "=== BibliotecAI Deployment ==="
echo ""

# 1. Pull latest code
echo "[1/5] Pulling latest changes from git..."
git pull origin main

# 2. Build the new image
echo ""
echo "[2/5] Building Docker image..."
docker compose -f "$COMPOSE_FILE" build web

# 3. Run migrations
echo ""
echo "[3/5] Running database migrations..."
docker compose -f "$COMPOSE_FILE" run --rm --no-deps web bin/rails db:migrate

# 4. Restart containers
echo ""
echo "[4/5] Restarting containers..."
docker compose -f "$COMPOSE_FILE" down
docker compose -f "$COMPOSE_FILE" up -d

# 5. Verify deployment
echo ""
echo "[5/5] Verifying deployment..."

# Retry health check up to 30 seconds
MAX_RETRIES=12
RETRY_INTERVAL=5
for i in $(seq 1 $MAX_RETRIES); do
    if curl -sf http://localhost:3012/up > /dev/null 2>&1; then
        echo ""
        echo "=== Deployment successful ==="
        docker compose -f "$COMPOSE_FILE" ps
        exit 0
    fi
    echo "  Waiting for app to start... ($i/$MAX_RETRIES)"
    sleep $RETRY_INTERVAL
done

echo ""
echo "=== WARNING: Health check failed after ${MAX_RETRIES} attempts ==="
echo "Check logs with: docker compose -f $COMPOSE_FILE logs web"
exit 1
