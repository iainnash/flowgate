#!/usr/bin/env bash
set -e

cd "$(dirname "$0")/../go-server"

echo "Building Go server..."
go build -o flowgate-server

echo "Starting server with VERBOSE=true..."
VERBOSE=true ./flowgate-server
