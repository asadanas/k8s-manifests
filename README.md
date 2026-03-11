# Kubernetes Deployment Guide for Laravel-Vue SPA
> GitOps-based deployment for the Laravel-Vue SPA application using Helm and ArgoCD.

## Repository Structure
```
k8s-manifests/
├── apps/
│ └── laravel-vue-app/                      # Helm chart for Laravel Vue SPA
│ ├── Chart.yaml                            # Helm chart metadata
│ ├── values-production.yaml                # Production configuration values
│ └── templates/                            # Kubernetes manifest templates
│ ├── _helpers.tpl                          # Helm template helpers
│ ├── configmap-env.yaml                    # Non-sensitive environment variables
│ ├── deployment-web.yaml                   # Laravel application deployment
│ ├── service-app.yaml                      # Kubernetes Service definition
│ ├── ingress.yaml                          # Ingress rules for external access
│ ├── job-migration.yaml                    # Database migration job (manual trigger)
│ └── redis/                                # Redis StatefulSet configuration
│ ├── headless-service.yaml
│ └── statefulset.yaml
├── argocd/
│ └── laravel-prod-app.yaml                 # ArgoCD Application manifest
├── k8s_HA_cluster_installation_guide.md    # Kubernetes cluster setup guide
└── README.md # This file
```
## Prerequisites

### Kubernetes Cluster Requirements
- Kubernetes 1.22+
- 4+ vCPUs, 6GB+ RAM (cluster total)
- `nfs-csi` StorageClass (for Redis persistence)
- Ingress Controller (e.g., nginx-ingress)
- Helm (to deploy application by using helm charts)
- ArgoCD (to deploy application safely)

### Install the Kubernetes cluster by following `k8s_HA_cluster_installation_guide.md` guide which exists in this repository. 

### Install Helm & ArgoCD

#### Install Helm
```bash
# Quick install (Linux/macOS)
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
# Verify installation
helm version
# Full installation options: https://helm.sh/docs/intro/install/
```
#### Install ArgoCD (HA for Production)
```bash
# Create dedicated namespace
kubectl create namespace argocd

# Install HIGH-AVAILABILITY version (recommended for 3-node clusters)
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/ha/install.yaml
# Official installation guide: https://argo-cd.readthedocs.io/en/stable/operator-manual/installation/
# Check ArgoCD pods
kubectl get pods -n argocd
# Expected output (all Running):
# argocd-server-*          1/1     Running
# argocd-repo-server-*     1/1     Running
# argocd-application-*     1/1     Running
```
### External Dependencies
- MySQL database 
- Docker Hub access
- DNS record pointing to Ingress Controller IP

## Project Structure Setup
### Creating the Helm Chart (Step-by-Step Guide)

This section walks you through creating the Helm chart structure from scratch, exactly as shown in the repository structure above.

### Step 1: CREATE GITHUB REPOSITORY
#### 1.1 Create New Repository
- Create on GitHub: https://github.com/new
- Repository name: k8s-manifests
- Description: Kubernetes manifests for Laravel Vue SPA
- Visibility: Private (recommended for production)
- Initialize with README: Yes

#### 1.2 Clone to Your Local Machine
```bash
git clone https://github.com/asadanas/k8s-manifests.git
cd k8s-manifests
```
### STEP 2: CREATE COMPLETE HELM CHART
#### 2.1 Create Directory Structure
```bash
mkdir -p apps/laravel-vue-app/templates/redis
mkdir -p argocd
vim apps/laravel-vue-app/Chart.yaml
vim apps/laravel-vue-app/values-production.yaml
vim apps/laravel-vue-app/templates/_helpers.tpl
vim apps/laravel-vue-app/templates/configmap-env.yaml
vim apps/laravel-vue-app/templates/redis/headless-service.yaml
vim apps/laravel-vue-app/templates/redis/statefulset.yaml
vim apps/laravel-vue-app/templates/job-migration.yaml
vim apps/laravel-vue-app/templates/deployment-web.yaml
vim apps/laravel-vue-app/templates/service-app.yaml
vim apps/laravel-vue-app/templates/ingress.yaml
```

### STEP 3: CREATE KUBERNETES SECRETS (MANUALLY)
#### 3.1 Create Namespace
```bash
kubectl create namespace production
```
#### 3.2 Create laravel-secrets (using YOUR EXACT values)

```bash
# Create application secrets (REPLACE <your_db_pass> with actual password)
kubectl create secret generic laravel-secrets \
  --namespace=production \
  --from-literal=APP_KEY="base64:sgztEi+QEaLgS+8MRSkG2X7cAE7pYEqIvKHKUrUfLhg=" \
  --from-literal=DB_HOST="<your_db_IP>" \
  --from-literal=DB_PASSWORD="<your_db_pass>" \
  --from-literal=REDIS_PASSWORD="null" \
  --from-literal=JWT_SECRET="A9it6bRt3rf4yeiDaADCI27ttFFH9WfhlqWySqqHG0W3ivM5PZdmSfSunZVcBvJU"
# Create database credentials
kubectl create secret generic db-credentials \
  --namespace=production \
  --from-literal=username="<your_db_user>" \
  --from-literal=password="<your_db_pass>"
  ```
#### 3.3 Create TLS Secret
```bash
# If you have TLS certificate files:
kubectl create secret tls spa-getnatai-com-tls \
  --namespace=production \
  --cert=path/to/tls.crt \
  --key=path/to/tls.key
```
### STEP 4: COMMIT & PUSH TO GITHUB
```bash
# Add all files
git add .
# Commit
git commit -m "Initial commit: Laravel Vue SPA Helm chart"
# Push to GitHub
git push origin main
```
### STEP 5: CREATE ARGOCD APPLICATION
#### 5.1 Create ArgoCD Application Manifest
```bash
vim argocd/laravel-prod-app.yaml
```
### 5.2 Apply ArgoCD Application
```bash
kubectl apply -f argocd/laravel-prod-app.yaml
```
### Verify Application in ArgoCD UI
```bash
# Get ArgoCD admin password
kubectl get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
# Port forward ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Open browser: https://localhost:8080
# Login with username: admin, password: (from above)
```
#### Or you can create ingress like following.
```bash
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-ingress
  namespace: argocd
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
spec:
  ingressClassName: nginx
  rules:
  - host: <your_domain>
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 443
# Open browser: https://<your_domain>
```
### STEP 6: VERIFICATION CHECKLIST
#### 6.1 Check Application
```bash
kubectl get application # I installed argocd in default namespace
```
#### 6.2 Check Deployment
```bash
kubectl get deployments -n production
kubectl get pods -n production
kubectl describe pod <pod-name> -n production
```
#### 6.3 Check Services
```bash
kubectl get svc -n production
kubectl describe svc laravel-vue-app-nginx -n production
```
#### 6.4 Check Ingress
```bash
kubectl get ingress -n production
kubectl describe ingress laravel-vue-app-ingress -n production
```
#### 6.5 Check Redis
```bash
kubectl get pods -n production -l app=redis
kubectl exec -it <redis-pod> -n production -- redis-cli ping
```
#### 6.6 Check Logs
```bash
# Web logs
kubectl logs -l app=web -n production --tail=50
# Worker logs
kubectl logs -l app=worker -n production --tail=50
# Redis logs
kubectl logs -l app=redis -n production --tail=50
```
### STEP 7: MONITORING & TROUBLESHOOTING
### Common Issues & Solutions
#### Issue: Pods stuck in Pending
```bash
kubectl describe pod <pod-name> -n production
# Check events for scheduling issues
```
#### Issue: ImagePullError
```bash
# Check image exists and is public
docker pull asadanas/laravel-vue-app:latest
```
#### Issue: Database connection failed
```bash
# Test DB connectivity
kubectl exec -it <web-pod> -n production -- sh
# Inside pod:
nc -zv <db_ip> 3306
```
#### Issue: Connection refused to Redis
```bash
# Test Redis connectivity from web pod
kubectl exec -it <web-pod> -n production -- sh
# Inside pod:
nc -zv <redis_service> 
```
#### Scale Deployments
##### Scale web app replicas
```bash
kubectl scale deployment production -n production --replicas=3
```
##### Scale nginx replicas
```bash
kubectl scale deployment laravel-nginx -n production --replicas=3
```
### STEP 8: Test Application Access
```bash
kubectl get ingress -n production
```
#### Expected Output
NAME              CLASS   HOSTS              ADDRESS         PORTS   AGE
laravel-ingress   nginx   spa.getnatai.com   10.102.139.33   80      13d
- Open the browser and try to access http://spa.getnatai.com. It should appear laravel application page. 
- Try to do registration by clicking the REGISTER button. 
- If you can register & login the application successfully, it is working properly.

#### App Returns 502 Bad Gateway
```bash
# Symptom: Browser shows 502 error when accessing site.
# Check Nginx logs
kubectl logs deployment/laravel-nginx -n production --tail=30

# Verify Nginx can reach PHP-FPM
kubectl exec deployment/laravel-nginx -n production -- \
  sh -c "nc -zv app 9000 && echo 'PHP-FPM reachable' || echo 'FAILED'"

# IF FAILED → Restart both tiers:
kubectl rollout restart deployment/laravel-app -n production
kubectl rollout restart deployment/laravel-nginx -n production
```
