# Kubernetes basics on AKS

A hands-on, beginner-friendly tour of the core Kubernetes building blocks, running on
Azure Kubernetes Service (AKS). Every manifest is small, heavily commented, and shows
**one concept**, so you can read a file, apply it, and see what it does.

You'll see:

- Deployments with replicas, ephemeral storage (`emptyDir`), requests/limits and a dedicated node pool
- Services: ClusterIP, NodePort, LoadBalancer
- Gateway API (the successor of Ingress) with [Envoy Gateway](https://gateway.envoyproxy.io/)
- ConfigMaps and Secrets as environment variables, files and directories, including a TLS certificate
- A DaemonSet, a StatefulSet with persistent disks, a CronJob and a CPU-based HorizontalPodAutoscaler

## What you need

| Tool | Used for |
|---|---|
| An Azure subscription | Hosting the cluster |
| [Azure CLI (`az`)](https://learn.microsoft.com/cli/azure/install-azure-cli) | Login and cluster credentials |
| [Terraform](https://developer.hashicorp.com/terraform/install) ≥ 1.15 | Creating the cluster (`terraform/`) |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | Talking to Kubernetes |
| [Helm](https://helm.sh/docs/intro/install/) | Installing Envoy Gateway |

> **💸 Cost:** the cluster is sized to be cheap, not free. You pay for 3 × `Standard_B2als_v2`
> nodes (about $0.04/h each), their disks, a load balancer and public IPs while it runs.
> Run `terraform destroy` when you're done (see [Clean up](#3-clean-up)).

## Quick start

```sh
# 1. Cluster (about 10 minutes)
az login
export TF_VAR_subscription_id=<your-subscription-id>     # from: az account list -o table
terraform -chdir=terraform init
terraform -chdir=terraform apply
az aks get-credentials --subscription $TF_VAR_subscription_id -g aks-demo -n aks-demo

# 2. Gateway API controller
helm install eg oci://docker.io/envoyproxy/gateway-helm --version v1.10.0 -n envoy-gateway-system --create-namespace

# 3. All demo resources
kubectl apply -f .
kubectl get all -n demo
```

Then follow the [walkthrough](#2-walk-through-each-concept) below, one concept at a time.

> Already have a cluster? Skip step 1. The manifests work on any AKS cluster that has an
> `apps` node pool. On other clusters, remove the `nodeSelector` from `20-deployment-web.yaml`
> and the `storageClassName` from `50-statefulset-redis.yaml`.

## What's in the repo

| Path | What it is |
|---|---|
| `terraform/` | A minimal AKS cluster: Free tier, public API, `system` + `apps` node pools |
| `*.yaml` | The demo manifests, numbered in apply order |

| File | Concept |
|---|---|
| `00-namespace.yaml` | Namespace `demo` (everything lives here) |
| `10-configmap-env.yaml` | ConfigMap used as environment variables |
| `11-configmap-file.yaml` | ConfigMap used as a file (nginx home page) |
| `12-secret-env.yaml` | Secret used as environment variables |
| `13-secret-files.yaml` | Secret mounted file by file (`subPath`) into an existing directory |
| `14-secret-tls.yaml` | TLS Secret (SSL cert + key) with base64 `data`, mounted as a directory |
| `20-deployment-web.yaml` | Deployment, 3 replicas, `emptyDir` cache, CPU/memory requests and limits, pinned to the `apps` node pool |
| `21-config-reader.yaml` | Pod that prints the ConfigMaps/Secrets it received |
| `30-service-clusterip.yaml` | Service: ClusterIP (internal only) |
| `31-service-nodeport.yaml` | Service: NodePort (port 30080 on every node) |
| `32-service-loadbalancer.yaml` | Service: LoadBalancer (public Azure IP) |
| `40-daemonset-node-exporter.yaml` | DaemonSet: one node-exporter per node |
| `50-statefulset-redis.yaml` | StatefulSet with a disk (PVC) per pod |
| `60-gateway.yaml` | Gateway API: GatewayClass + Gateway + HTTPRoute |
| `70-cronjob.yaml` | CronJob, runs every minute |
| `80-hpa.yaml` | HorizontalPodAutoscaler on CPU |

## 0. Prerequisites

- An AKS cluster. `terraform/` creates a cheap one in `polandcentral`: Free tier, public API, a `system` node pool (2 × `Standard_B2als_v2`) and an `apps` node pool (1 × `Standard_B2als_v2`):

```sh
az login
az account list -o table                                   # pick your subscription ID
export TF_VAR_subscription_id=<your-subscription-id>

terraform -chdir=terraform init
terraform -chdir=terraform apply
az aks get-credentials --subscription $TF_VAR_subscription_id -g aks-demo -n aks-demo
```

  Change `location` in `terraform/main.tf` to deploy elsewhere.

- Helm, for installing Envoy Gateway (the Gateway API controller):

```sh
helm install eg oci://docker.io/envoyproxy/gateway-helm --version v1.10.0 -n envoy-gateway-system --create-namespace
kubectl wait --timeout=5m -n envoy-gateway-system deployment/envoy-gateway --for=condition=Available
```

## 1. Apply everything

```sh
kubectl apply -f .
kubectl get all -n demo
```

## 2. Walk through each concept

### Deployment and ephemeral storage

```sh
kubectl get deploy,pods -n demo -l app=web          # 3 pods
kubectl delete pod -n demo -l app=web --wait=false  # kill them all...
kubectl get pods -n demo -l app=web                 # ...new ones are created
kubectl scale deploy web -n demo --replicas=5       # more copies
```

The `web` pods run only on the `apps` node pool (`nodeSelector` in the Deployment):

```sh
kubectl get nodes -L kubernetes.azure.com/agentpool   # which node belongs to which pool
kubectl get pods -n demo -l app=web -o wide           # NODE column: all on aks-apps-...
```

Requests and limits: what each `web` pod reserves vs. what it actually uses:

```sh
kubectl describe node -l kubernetes.azure.com/agentpool=apps | grep -A8 "Allocated resources"
kubectl top pods -n demo -l app=web
```

The `emptyDir` cache is deleted together with its pod:

```sh
POD=$(kubectl get pod -n demo -l app=web -o name | head -1)
kubectl exec -n demo $POD -- sh -c 'echo hello > /var/cache/nginx/test.txt; ls /var/cache/nginx'
kubectl delete -n demo $POD
# the replacement pod starts with an empty cache directory
```

### ConfigMaps and Secrets

```sh
kubectl logs -n demo config-reader         # env vars and secret files, as the app sees them
kubectl get secret db-credentials -n demo -o yaml   # values are base64, NOT encrypted
```

Two ways to mount a Secret as files:

- **File by file (`subPath`)**: the API keys land as single files inside the existing `/etc`, and the rest of `/etc` stays visible. These files do NOT update when the Secret changes.
- **Whole directory**: the TLS Secret becomes the directory `/etc/tls`, one file per key. These files DO update when the Secret changes (within about a minute).

```sh
kubectl exec -n demo config-reader -- ls /etc            # payment-api.key and weather-api.key next to passwd, hosts, ...
kubectl exec -n demo config-reader -- cat /etc/payment-api.key
kubectl exec -n demo config-reader -- ls -l /etc/tls     # tls.crt -> ..data/tls.crt (symlinks)
```

Why only the directory updates: its files are symlinks into a hidden `..data` folder, which Kubernetes swaps all at once when the Secret changes. A `subPath` file is a plain copy made when the container starts.

TLS Secret: stored as base64 in the YAML, but a normal PEM file inside the pod:

```sh
kubectl exec -n demo config-reader -- head -1 /etc/tls/tls.crt          # -----BEGIN CERTIFICATE-----
kubectl get secret demo-tls -n demo -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -subject -enddate
```

ConfigMap as a file is the nginx home page. See it through any Service below.

### Services

```sh
kubectl get svc -n demo
```

ClusterIP (internal only). Call it from a throwaway pod inside the cluster:

```sh
kubectl run tmp -n demo --rm -it --image=busybox:1.37 --restart=Never -- wget -qO- http://web
```

NodePort. AKS nodes only have private IPs, so call it from inside the cluster too:

```sh
kubectl get nodes -o wide                  # copy an INTERNAL-IP
kubectl run tmp -n demo --rm -it --image=busybox:1.37 --restart=Never -- wget -qO- http://<INTERNAL-IP>:30080
```

LoadBalancer (public). Wait for an `EXTERNAL-IP`, then open it in a browser:

```sh
kubectl get svc web-public -n demo -w
```

### DaemonSet

```sh
kubectl get nodes
kubectl get pods -n demo -l app=node-exporter -o wide   # one pod per node
kubectl port-forward -n demo daemonset/node-exporter 9100:9100
# open http://localhost:9100/metrics
```

### StatefulSet with PVC

```sh
kubectl get pods,pvc -n demo -l app=redis        # redis-0, redis-1, each with its own PVC
kubectl exec -n demo redis-0 -- redis-cli set greeting "I survive restarts"
kubectl delete pod -n demo redis-0               # recreated with the same name and disk
kubectl wait -n demo --for=condition=Ready pod/redis-0
kubectl exec -n demo redis-0 -- redis-cli get greeting
```

### Gateway API

```sh
kubectl get gateway,httproute -n demo
GW=$(kubectl get gateway web-gateway -n demo -o jsonpath='{.status.addresses[0].value}')
curl http://$GW/
```

### CronJob

```sh
kubectl get cronjob,jobs -n demo -w        # a new Job every minute
kubectl logs -n demo -l job-name --tail=1 --prefix
```

### HorizontalPodAutoscaler

Terminal 1, watch:

```sh
kubectl get hpa,pods -n demo -l app=php-apache -w
```

Terminal 2, generate load (Ctrl+C to stop):

```sh
kubectl run load -n demo --rm -it --image=busybox:1.37 --restart=Never -- sh -c "while true; do wget -qO- http://php-apache; done"
```

CPU rises above 50% and replicas go up to 5. After you stop the load, it takes about 5 minutes to scale back down.

## 3. Clean up

```sh
kubectl delete namespace demo     # also deletes the PVCs and Azure disks
kubectl delete gatewayclass eg
helm uninstall eg -n envoy-gateway-system
```

Or remove the whole cluster (stops all costs):

```sh
terraform -chdir=terraform destroy
```

## Notes

- **The secrets in this repo are fake demo values.** That includes the self-signed TLS certificate and
  private key in `14-secret-tls.yaml`. Never commit real secrets to git, and remember that
  base64 is encoding, not encryption.
- The cluster runs on x86 nodes because the `hpa-example` image used for the autoscaler demo
  is published for amd64 only.

## License

[MIT](LICENSE)
