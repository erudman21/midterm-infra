#!/bin/bash
set -e

# Test frontend
if ! curl --silent --fail --max-time 10 http://localhost:80; then
    echo "Frontend failed"
    exit 1
fi
echo "Frontend works"

# Test backend
if ! curl --silent --fail --max-time 10 http://localhost:9080/users; then
    echo "Backend failed"
    exit 1
fi
echo "Backend works"

# Test basic db stuff
create_response=$(curl -s -X POST -H "Content-Type: application/json" -d '{"firstName":"Test","lastName":"User","email":"test@example.com"}' http://localhost:9080/users)
if [[ "$create_response" != *"New user was created"* ]]; then
    echo "DB failed"
    exit 1
fi
echo "DB works"
echo "All smoke tests worked"