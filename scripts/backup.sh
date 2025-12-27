#!/bin/bash

# Usage: ./backup.sh
# Cron: 0 2 * * * /path/to/backup.sh

set -e

# Configuration
BACKUP_DIR="/backups/monitoring"
DATE=$(date +%Y%m%d-%H%M%S)
RETENTION_DAYS=7

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Monitoring Stack Backup${NC}"
echo -e "${GREEN}Started: $(date)${NC}"
echo -e "${GREEN}========================================${NC}"

mkdir -p "$BACKUP_DIR"

echo -e "\n${YELLOW}[1/4] Backing up Grafana...${NC}"

if docker volume inspect grafana-data >/dev/null 2>&1; then
    docker run --rm \
        -v grafana-data:/data \
        -v "$BACKUP_DIR":/backup \
        alpine tar czf /backup/grafana-$DATE.tar.gz /data
    
    echo -e "${GREEN}✓ Grafana backup completed${NC}"
    ls -lh "$BACKUP_DIR/grafana-$DATE.tar.gz"
else
    echo -e "${RED}✗ Grafana volume not found${NC}"
fi

echo -e "\n${YELLOW}[2/4] Backing up Prometheus...${NC}"

if docker ps --filter "name=prometheus" --filter "status=running" -q >/dev/null 2>&1; then
    # Create snapshot via API (requires --web.enable-admin-api)
    if docker exec prometheus wget -qO- --post-data='' http://localhost:9090/api/v1/admin/tsdb/snapshot 2>/dev/null; then
        echo -e "${GREEN}✓ Prometheus snapshot created${NC}"
        
        # Copy snapshot to backup
        SNAPSHOT_DIR=$(docker exec prometheus ls -t /prometheus/snapshots | head -1)
        if [ ! -z "$SNAPSHOT_DIR" ]; then
            docker cp prometheus:/prometheus/snapshots/$SNAPSHOT_DIR "$BACKUP_DIR/prometheus-$DATE"
            echo -e "${GREEN}✓ Prometheus snapshot backed up${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ Prometheus API snapshot failed, using volume backup${NC}"
        
        # Fallback: Direct volume backup
        docker run --rm \
            -v prometheus-data:/data \
            -v "$BACKUP_DIR":/backup \
            alpine tar czf /backup/prometheus-data-$DATE.tar.gz /data
        
        echo -e "${GREEN}✓ Prometheus volume backed up${NC}"
    fi
else
    echo -e "${RED}✗ Prometheus container not running${NC}"
fi

echo -e "\n${YELLOW}[3/4] Backing up configuration files...${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

tar czf "$BACKUP_DIR/configs-$DATE.tar.gz" \
    -C "$SCRIPT_DIR" \
    docker-compose.yml \
    prometheus/ \
    grafana/provisioning/ \
    alertmanager/ \
    .env 2>/dev/null || true

echo -e "${GREEN}✓ Configuration files backed up${NC}"
ls -lh "$BACKUP_DIR/configs-$DATE.tar.gz"

echo -e "\n${YELLOW}[4/4] Cleaning up old backups (>$RETENTION_DAYS days)...${NC}"

DELETED_COUNT=$(find "$BACKUP_DIR" -type f -mtime +$RETENTION_DAYS -delete -print | wc -l)
DELETED_DIRS=$(find "$BACKUP_DIR" -type d -empty -delete -print | wc -l)

echo -e "${GREEN}✓ Deleted $DELETED_COUNT old backup files${NC}"
echo -e "${GREEN}✓ Deleted $DELETED_DIRS empty directories${NC}"

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}Backup Summary${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "Backup location: ${YELLOW}$BACKUP_DIR${NC}"
echo -e "Backup date: ${YELLOW}$DATE${NC}"
echo -e "\nBackup files created:"
ls -lh "$BACKUP_DIR" | grep "$DATE"

TOTAL_SIZE=$(du -sh "$BACKUP_DIR" | cut -f1)
echo -e "\nTotal backup size: ${YELLOW}$TOTAL_SIZE${NC}"

echo -e "\n${GREEN}Backup completed successfully at $(date)${NC}"
echo -e "${GREEN}========================================${NC}"

# Optional: Send notification (uncomment if Alertmanager is configured)
# curl -X POST http://localhost:9093/api/v1/alerts -d '[{"labels":{"alertname":"BackupCompleted","severity":"info"},"annotations":{"summary":"Monitoring backup completed","description":"Backup size: '$TOTAL_SIZE'"}}]'
