#!/bin/bash
set -e

# Determine the repository root relative to this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
APP_DIR="$REPO_ROOT/kubernetes/apps/media"

echo "🔍 Validating Kustomize Manifests..."

# 1. Build Kustomize
echo "---------------------------------------------------"
echo "1. Building Kustomize..."
if MANIFESTS=$(kubectl kustomize "$APP_DIR"); then
    echo "✅ [BUILD] Kustomize build succeeded."
else
    echo "❌ [BUILD] Kustomize build FAILED."
    exit 1
fi

# 2. Schema Validation (Prefer kubeconform, fallback to kubectl dry-run)
echo "---------------------------------------------------"
echo "2. Validating Schemas..."

if command -v kubeconform &> /dev/null; then
    echo "ℹ️  Using kubeconform for offline schema validation..."
    # Validate against standard K8s + common CRDs (if you configure schema locations, but basic k8s is good start)
    echo "$MANIFESTS" | kubeconform -summary -ignore-missing-schemas -strict
    echo "✅ [VALIDATION] kubeconform passed."

elif kubectl api-resources &> /dev/null; then
    echo "ℹ️  Cluster reachable. Using client-side dry-run..."
    echo "$MANIFESTS" | kubectl apply -f - --dry-run=client --validate=strict
    echo "✅ [VALIDATION] kubectl dry-run passed."

else
    echo "⚠️  [SKIP] No cluster reachable and 'kubeconform' not found."
    echo "    To enable offline validation, install kubeconform: https://github.com/yannh/kubeconform"
    # Do not fail the script, just warn
    exit 0
fi
