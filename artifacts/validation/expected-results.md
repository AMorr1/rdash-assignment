# Expected Validation Results

This file is the human-readable checklist paired with `scripts/capture_validation.sh`.

- `namespaces.txt`: success
- `default_pods.txt`: forbidden
- `kube_system_pods.txt`: forbidden
- `rbac_a_get.txt`: success
- `rbac_a_create.txt`: forbidden
- `rbac_b_get.txt`: success
- `rbac_b_create.txt`: success
- `rbac_b_delete.txt`: success

Add live run outputs under `artifacts/validation/run-<timestamp>/` before submission.
