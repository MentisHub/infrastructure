#!/bin/sh

set -e

echo "Creating 'fab' bucket..."

RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "http://supabase-storage:5000/bucket" \
  -H "Authorization: Bearer ${SERVICE_ROLE_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "id": "fab",
    "name": "fab",
    "public": false,
    "file_size_limit": 52428800,
    "allowed_mime_types": ["application/octet-stream"]
  }')

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
  echo "Bucket 'fab' created successfully"
  echo "  Response: $BODY"
elif echo "$BODY" | grep -qi "already exists\|duplicate"; then
  echo "Bucket 'fab' already exists"
else
  echo "Warning: Unexpected response when creating bucket 'fab'"
  echo "  HTTP Code: $HTTP_CODE"
  echo "  Response: $BODY"
fi
