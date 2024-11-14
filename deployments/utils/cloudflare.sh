#!/bin/bash

# Replace <YOUR_ZONE_ID> and <YOUR_API_TOKEN> with your Cloudflare details
CLOUDFLARE_ZONE_ID=${CLOUDFLARE_ZONE_ID:-"5c9b60928da3935db7db9dfa7d91452b"}
CLOUDFLARE_API_TOKEN=${CLOUDFLARE_API_TOKEN:-"IrdarobCCiw-MzA5qe3Wx8sy7xQ6PiOssigVM8A9"}
RECORD_NAME=${RECORD_NAME:-"grafana.nthedao.info"}  # Or use "sub.nthedao.info" for a subdomain
SUB_DOMAIN_NAME=${SUB_DOMAIN_NAME:-"nthedao.info"}  # Or use "sub.nthedao.info" for a subdomain

# Get current IP
IP=$(curl -s http://ipv4.icanhazip.com)

RECORD_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=${RECORD_NAME}" \
  -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
  -H "Content-Type: application/json" | jq -r '.result[0].id')

# Check if RECORD_ID was retrieved successfully
if [ -z "$RECORD_ID" ]; then
  echo "Error: Could not retrieve RECORD_ID for $RECORD_NAME"
  exit 1
fi

# Update Cloudflare DNS record
curl -X PUT "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records/$RECORD_ID" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data "{\"type\":\"A\",\"name\":\"$RECORD_NAME\",\"content\":\"$IP\",\"ttl\":1,\"proxied\":false}"
