#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${1:-artifacts/validation/run-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUT_DIR"

capture() {
  local name="$1"
  shift
  {
    echo "$ $*"
    "$@"
  } >"$OUT_DIR/$name.txt" 2>&1 || true
}

capture namespaces kubectl exec -n default pod/rbac-validation -- kubectl get namespaces
capture default_pods kubectl exec -n default pod/rbac-validation -- kubectl get pods -n default
capture kube_system_pods kubectl exec -n default pod/rbac-validation -- kubectl get pods -n kube-system
capture rbac_a_get kubectl exec -n default pod/rbac-validation -- kubectl get pods -n rbac-a
capture rbac_a_create kubectl exec -n default pod/rbac-validation -- kubectl create deployment nginx --image=nginx -n rbac-a
capture rbac_b_get kubectl exec -n default pod/rbac-validation -- kubectl get pods -n rbac-b
capture rbac_b_create kubectl exec -n default pod/rbac-validation -- kubectl create deployment nginx --image=nginx -n rbac-b
capture rbac_b_delete kubectl exec -n default pod/rbac-validation -- kubectl delete deployment nginx -n rbac-b

echo "Validation output written to $OUT_DIR"

