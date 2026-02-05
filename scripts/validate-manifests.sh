#!/bin/bash
set -e

# Determine the repository root relative to this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
APP_DIR="$REPO_ROOT/kubernetes/apps/media"

echo "🔍 Validating Kustomize Manifests..."

# 1. Check if kustomize builds without error
echo "---------------------------------------------------"
echo "1. Building Kustomize..."
if kubectl kustomize "$APP_DIR" > /dev/null; then
    echo "✅ [BUILD] Kustomize build succeeded."
else
    echo "❌ [BUILD] Kustomize build FAILED."
    exit 1
fi

# 2. Check if the output is valid Kubernetes YAML (Dry Run)
echo "---------------------------------------------------"
echo "2. Validating against Kubernetes API (Client-Side Dry Run)..."
# Note: This requires connectivity to the cluster to check CRDs/Schema compliance
kubectl kustomize "$APP_DIR" | kubectl apply -f - --dry-run=client --validate=strict

if [ $? -eq 0 ]; then
    echo "---------------------------------------------------"
    echo "✅ [VALIDATION] Manifests are syntactically valid."
else
    echo "---------------------------------------------------"
    echo "❌ [VALIDATION] Manifests failed validation."
    exit 1
fi
