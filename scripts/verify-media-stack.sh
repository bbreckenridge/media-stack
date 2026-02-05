#!/bin/bash
set -e

NAMESPACE="media"
echo "🔍 Starting NIST Compliance & Health Verification for Namespace: $NAMESPACE"

# 1. Workload Health Check
echo "---------------------------------------------------"
echo "1. Checking Workload Health (StatefulSets/Deployments)..."
statefulsets=$(kubectl get statefulset -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}')
for app in $statefulsets; do
    replicas=$(kubectl get statefulset $app -n $NAMESPACE -o jsonpath='{.status.readyReplicas}')
    if [[ "$replicas" == "1" ]]; then
        echo "✅ [HEALTH] $app is Ready."
    else
        echo "❌ [HEALTH] $app is NOT Ready (Ready Replicas: ${replicas:-0})."
        # Not failing script here to allow other checks to run
    fi
done

# 2. NIST Security Context Compliance (AC-6, SI-7)
echo "---------------------------------------------------"
echo "2. Verifying Container Hardening (SecurityContext)..."
pods=$(kubectl get pods -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}')
for pod in $pods; do
    # Check ReadOnlyRootFilesystem
    ro_fs=$(kubectl get pod $pod -n $NAMESPACE -o jsonpath='{.spec.containers[*].securityContext.readOnlyRootFilesystem}')
    if [[ "$ro_fs" == *"true"* ]]; then
        echo "✅ [SEC] $pod: Read-Only Root Filesystem Enforced."
    else
        echo "❌ [SEC] $pod: Read-Only Root Verify FAILED (Value: $ro_fs)."
    fi

    # Check Non-Root
    non_root=$(kubectl get pod $pod -n $NAMESPACE -o jsonpath='{.spec.securityContext.runAsNonRoot}')
    if [[ "$non_root" == "true" ]]; then
        echo "✅ [SEC] $pod: RunAsNonRoot Enforced."
    else
        echo "❌ [SEC] $pod: RunAsNonRoot Verify FAILED."
    fi

    # Check Drop Capabilities
    drop_caps=$(kubectl get pod $pod -n $NAMESPACE -o jsonpath='{.spec.containers[*].securityContext.capabilities.drop}')
    if [[ "$drop_caps" == *"ALL"* ]]; then
        echo "✅ [SEC] $pod: Capabilities Drop 'ALL' Enforced."
    else
        echo "❌ [SEC] $pod: Capabilities Verify FAILED (Value: $drop_caps)."
    fi
done

# 3. Network & Auth Policy Verification (SC-7, IA-2)
echo "---------------------------------------------------"
echo "3. Verifying Network & Auth Policies (Connectivity Tests)..."

# Temporary pod for testing
TEST_POD="probe-$(date +%s)"
echo "🚀 Spawning temporary probe pod ($TEST_POD)..."
kubectl run $TEST_POD -n $NAMESPACE --image=curlimages/curl --restart=Never -- sleep 300
echo "⏳ Waiting for probe pod..."
kubectl wait --for=condition=Ready pod/$TEST_POD -n $NAMESPACE --timeout=30s

# Test 3.1: Metrics Port (Should be ALLOWED without Token)
echo "   -> Testing Metrics Port (9794) - Expecting HTTP 200..."
http_code=$(kubectl exec -n $NAMESPACE $TEST_POD -- curl -s -o /dev/null -w "%{http_code}" http://prowlarr:9794/metrics || echo "fail")
if [[ "$http_code" == "200" ]]; then
    echo "✅ [NET] Metrics Port Access Allowed (HTTP 200)."
else
    echo "❌ [NET] Metrics Port Access FAILED (Code: $http_code)."
fi

# Test 3.2: Application Port (Should be DENIED without Token due to AuthPolicy)
echo "   -> Testing App Port (9696) - Expecting HTTP 403/401 (Auth Required)..."
http_code=$(kubectl exec -n $NAMESPACE $TEST_POD -- curl -s -o /dev/null -w "%{http_code}" http://prowlarr:9696 || echo "fail")
if [[ "$http_code" == "403" ]] || [[ "$http_code" == "401" ]]; then
    echo "✅ [AUTH] Unauthenticated Access Denied (HTTP $http_code)."
else
    echo "❌ [AUTH] Policy Leak! Got HTTP $http_code (Expected 403/401)."
fi

# Cleanup
echo "🧹 Cleaning up..."
kubectl delete pod $TEST_POD -n $NAMESPACE --force --grace-period=0 > /dev/null

echo "---------------------------------------------------"
echo "🎉 Verification Complete."
