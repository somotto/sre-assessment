# Scenario 1 — Pods Running But Application is Unreachable

## My Initial Thinking

The pods are Running, so the application itself probably started fine. The problem is somewhere between the outside world and those pods — meaning the traffic is getting lost at the Service, Ingress, or network layer before it even reaches the app. Since no code changes were made, I'd lean toward a misconfigured Service selector, a broken Ingress rule, or something Azure-specific like a Network Security Group blocking the load balancer port.

---

## 1. First 3 kubectl Commands

```bash
# Check if the Service has endpoints — if ENDPOINTS shows <none>, traffic has nowhere to go
kubectl get endpoints -n <namespace>

# Look at the Ingress to see if it has an ADDRESS assigned and what rules are configured
kubectl get ingress -n <namespace>

# Describe the Service to check the selector matches the pod labels
kubectl describe service <service-name> -n <namespace>
```

Why these three first? Because pods are already confirmed Running, so I skip the Deployment and go straight to the networking chain. No endpoints means the Service selector is wrong. No address on the Ingress means the load balancer never came up. A selector mismatch on the Service is one of the most common silent failures.

---

## 2. Which Resource to Check First and Why

I'd go in this order: **Service to Ingress and then to NSG**. Here's my reasoning:

**Service first** — the pods are running but if the Service selector doesn't match the pod labels, no traffic will ever reach them. This is a very common mistake and it's invisible unless you check endpoints. If `kubectl get endpoints` shows `<none>`, that's your answer right there.

**Ingress second** — if the Service looks fine, I check the Ingress. The Ingress controller is what actually handles the external URL. If the Ingress has no ADDRESS, the load balancer either failed to provision or the ingress controller itself isn't running. I'd also check that the Ingress `serviceName` and `servicePort` match exactly what the Service exposes.

**NSG / Azure networking last** — I check this after confirming the Kubernetes resources look correct, because NSG issues don't show up in kubectl at all. If everything in the cluster looks right but traffic still times out, the problem is almost certainly at the Azure network layer.

I skip the Deployment entirely at this stage, pods are Running, so the Deployment did its job.

---

## 3. How to Isolate Which Layer the Problem Is At

**Pod level** — exec into the pod and curl localhost on the port the app listens on:
```bash
kubectl exec -it <pod-name> -n <namespace> -- curl http://localhost:<app-port>
```
If this fails, the app isn't actually listening — even though the pod shows Running.

**Service level** — run a temporary pod inside the cluster and curl the Service's ClusterIP:
```bash
kubectl run test --image=curlimages/curl -it --rm --restart=Never -- curl http://<service-clusterip>:<port>
```
If the pod-level test passed but this fails, the Service selector is wrong or the port mapping is off.

**Ingress / network level** — if the Service test passed, try curling the Ingress address from inside the cluster, then from outside:
```bash
# From inside the cluster
kubectl run test --image=curlimages/curl -it --rm --restart=Never -- curl http://<ingress-address>

# From your machine
curl -v http://<external-url>
```
A timeout from outside but success from inside points to the Azure load balancer or NSG blocking external traffic.

---

## 4. Two Azure-Specific Things That Could Cause This

**1. Network Security Group (NSG) blocking the load balancer port**

AKS nodes sit behind an NSG that Azure manages. Sometimes a rule gets added (or a default rule takes priority) that blocks inbound traffic on port 80 or 443 to the node pool. Everything in Kubernetes looks fine — Service has endpoints, Ingress has an address — but traffic dies at the Azure network boundary before reaching the nodes. You'd check this in the Azure Portal under the node resource group → NSG → Inbound security rules.

**2. Azure Load Balancer not provisioned or in a failed state**

When you create a Kubernetes Service of type `LoadBalancer`, AKS automatically provisions an Azure Load Balancer. If the service principal or managed identity that AKS uses doesn't have enough permissions on the resource group, the load balancer either never gets created or gets stuck in a failed provisioning state. The Ingress address stays pending indefinitely. You'd spot this by checking `kubectl describe service <name>` for events mentioning provisioning errors, and then checking the Azure Load Balancer resource in the portal to see if it actually exists.
