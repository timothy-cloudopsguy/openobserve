#!/bin/bash

term() {

    echo "=========================================="
    echo "PreStop Hook Started: $(date)"
    echo "Node: $HOSTNAME"
    echo "=========================================="

    PRIVATE_IP=$(ip -o route get 8.8.8.8 | awk '{print $7}')

    # Get credentials from environment
    AUTH_HEADER=$(echo -n "${ZO_ROOT_USER_EMAIL}:${ZO_ROOT_USER_PASSWORD}" | base64)

    # Step 1: Disable the node (triggers drain mode)
    echo "[$(date)] Step 1: Calling PUT /node/enable?value=false to disable node..."
    DISABLE_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
    -X PUT "http://${PRIVATE_IP}:${ZO_HTTP_PORT}/node/enable?value=false" \
    -H "Authorization: Basic ${AUTH_HEADER}")

    HTTP_CODE=$(echo "$DISABLE_RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
    BODY=$(echo "$DISABLE_RESPONSE" | grep -v "HTTP_CODE:")

    echo "[$(date)] Response (HTTP $HTTP_CODE): $BODY"

    if [ "$HTTP_CODE" != "200" ]; then
        echo "[$(date)] ERROR: Failed to disable node"
        exit 1
    fi

    echo "[$(date)] ✓ Node disabled - drain mode activated"
    echo ""

    # Step 2: Poll drain status until ready for shutdown
    echo "[$(date)] Step 2: Monitoring drain status via GET /node/drain_status..."

    START_TIME=$(date +%s)
    MAX_WAIT=1000  # ~16 minutes (leave buffer for k8s)
    POLL_INTERVAL=5

    while true; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))

    if [ $ELAPSED -ge $MAX_WAIT ]; then
        echo "[$(date)] WARNING: Drain timeout after ${ELAPSED}s"
        echo "[$(date)] Exiting to allow ECS Fargate to terminate node"
        break
    fi

    # Call drain_status API
    STATUS=$(curl -s "http://${PRIVATE_IP}:${ZO_HTTP_PORT}/node/drain_status" \
        -H "Authorization: Basic ${AUTH_HEADER}")

    if [ $? -ne 0 ]; then
        echo "[$(date)] ERROR: Failed to get drain status"
        sleep $POLL_INTERVAL
        continue
    fi

    # Parse JSON response (without jq dependency)
    READY=$(echo "$STATUS" | grep -o '"readyForShutdown":[^,}]*' | cut -d: -f2 | tr -d ' ')
    PENDING=$(echo "$STATUS" | grep -o '"pendingParquetFiles":[^,}]*' | cut -d: -f2 | tr -d ' ')
    IS_DRAINING=$(echo "$STATUS" | grep -o '"isDraining":[^,}]*' | cut -d: -f2 | tr -d ' ')
    MEMORY_FLUSHED=$(echo "$STATUS" | grep -o '"memoryFlushed":[^,}]*' | cut -d: -f2 | tr -d ' ')

    echo "[$(date)] [${ELAPSED}s] Status:"
    echo "  - isDraining: $IS_DRAINING"
    echo "  - memoryFlushed: $MEMORY_FLUSHED"
    echo "  - pendingParquetFiles: $PENDING"
    echo "  - readyForShutdown: $READY"

    # Check if ready for shutdown
    if [ "$READY" = "true" ]; then
        echo ""
        echo "=========================================="
        echo "[$(date)] ✓ DRAIN COMPLETED in ${ELAPSED}s"
        echo "=========================================="
        echo "All parquet files uploaded to S3"
        echo "Node is safe to terminate"
        break
    fi

    sleep $POLL_INTERVAL
    done

    echo "[$(date)] PreStop hook completed. Node will now terminate."


    kill -TERM "$child"
    wait "$child"
    exit 0

}

# Trap signals from ECS Fargate to trigger the pre-stop hook
trap term SIGTERM SIGINT

# Set the private IP address of the node
PRIVATE_IP=$(ip -o route get 8.8.8.8 | awk '{print $7}')
export ZO_HTTP_ADDR="${PRIVATE_IP}"
export ZO_GRPC_ADDR="${PRIVATE_IP}"

/openobserve "$@" &
child=$!
wait "$child"