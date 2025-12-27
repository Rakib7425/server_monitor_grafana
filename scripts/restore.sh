# !/bin/bash


# Usage: ./restore.sh <backup-date>
# Example: ./restore.sh 20231226-140530

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <backup-date>"
    echo "Example: $0 20231226-140530"
    echo ""
    echo "Available backups:"
    ls -1 /backups/monitoring/*.tar.gz 2>/dev/null | sed 's/.*-\([0-9-]*\)\.tar\.gz/\1/' | sort -u
    exit 1
fi

BACKUP_DATE=$1
BACKUP_DIR="/backups/monitoring"

echo "=========================================="
echo "Monitoring Stack Restore"
echo "Restoring from backup: $BACKUP_DATE"
echo "=========================================="

# Stop containers
echo ""
echo "[1/4] Stopping containers..."
docker-compose down

# Restore Grafana
echo ""
echo "[2/4] Restoring Grafana..."
if [ -f "$BACKUP_DIR/grafana-$BACKUP_DATE.tar.gz" ]; then
    docker volume rm grafana-data 2>/dev/null || true
    docker volume create grafana-data
    docker run --rm \
        -v grafana-data:/data \
        -v "$BACKUP_DIR":/backup \
        alpine tar xzf /backup/grafana-$BACKUP_DATE.tar.gz -C /
    echo "✓ Grafana restored"
else
    echo "⚠ Grafana backup not found"
fi

# Restore Prometheus
echo ""
echo "[3/4] Restoring Prometheus..."
if [ -f "$BACKUP_DIR/prometheus-data-$BACKUP_DATE.tar.gz" ]; then
    docker volume rm prometheus-data 2>/dev/null || true
    docker volume create prometheus-data
    docker run --rm \
        -v prometheus-data:/data \
        -v "$BACKUP_DIR":/backup \
        alpine tar xzf /backup/prometheus-data-$BACKUP_DATE.tar.gz -C /
    echo "✓ Prometheus restored"
elif [ -d "$BACKUP_DIR/prometheus-$BACKUP_DATE" ]; then
    docker volume create prometheus-data
    docker run --rm \
        -v prometheus-data:/prometheus \
        -v "$BACKUP_DIR/prometheus-$BACKUP_DATE":/backup \
        alpine cp -r /backup /prometheus/snapshots/
    echo "✓ Prometheus snapshot restored"
else
    echo "⚠ Prometheus backup not found"
fi

# Restore configurations
echo ""
echo "[4/4] Restoring configurations..."
if [ -f "$BACKUP_DIR/configs-$BACKUP_DATE.tar.gz" ]; then
    tar xzf "$BACKUP_DIR/configs-$BACKUP_DATE.tar.gz"
    echo "✓ Configurations restored"
else
    echo "⚠ Configuration backup not found"
fi

# Start containers
echo ""
echo "Starting containers..."
docker-compose up -d

echo ""
echo "=========================================="
echo "Restore completed successfully!"
echo "=========================================="
echo "Please verify:"
echo "1. docker-compose ps"
echo "2. Access Grafana: http://localhost:6566"
echo "=========================================="
