# Validation Commands

Run these after `helm upgrade --install rbac-validation ...` and after the cluster workload identity federation has propagated.

## RBAC validation

```bash
kubectl exec -n default pod/rbac-validation -- kubectl get namespaces
kubectl exec -n default pod/rbac-validation -- kubectl get pods -n default
kubectl exec -n default pod/rbac-validation -- kubectl get pods -n kube-system
kubectl exec -n default pod/rbac-validation -- kubectl get pods -n rbac-a
kubectl exec -n default pod/rbac-validation -- kubectl create deployment nginx --image=nginx -n rbac-a
kubectl exec -n default pod/rbac-validation -- kubectl get pods -n rbac-b
kubectl exec -n default pod/rbac-validation -- kubectl create deployment nginx --image=nginx -n rbac-b
kubectl exec -n default pod/rbac-validation -- kubectl delete deployment nginx -n rbac-b
```

Expected results:

- `kubectl get namespaces`: success
- `kubectl get pods -n default`: forbidden
- `kubectl get pods -n kube-system`: forbidden
- `kubectl get pods -n rbac-a`: success
- `kubectl create deployment ... -n rbac-a`: forbidden
- `kubectl get pods -n rbac-b`: success
- `kubectl create deployment ... -n rbac-b`: success
- `kubectl delete deployment ... -n rbac-b`: success

## Blob validation

```bash
kubectl exec -n default pod/rbac-validation -- sh -c 'echo hello > /tmp/hello.txt'
kubectl exec -n default pod/rbac-validation -- az storage blob upload --auth-mode login --file /tmp/hello.txt --container-name worker-results --name hello.txt --account-name <storage-account>
kubectl exec -n default pod/rbac-validation -- az storage blob download --auth-mode login --container-name worker-results --name hello.txt --file /tmp/hello-downloaded.txt --account-name <storage-account>
kubectl exec -n default pod/rbac-validation -- cat /tmp/hello-downloaded.txt
```

## Service smoke tests

```bash
curl -i https://core.<domain>/healthz
curl -i https://registry.<domain>/healthz
curl -X POST https://core.<domain>/v1/tasks -H 'content-type: application/json' -d '{"job":"demo"}'
```

