# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a GitOps repository for deploying Ghost (blogging platform) with MySQL backend on a K3s Kubernetes cluster using ArgoCD for continuous deployment. The deployment uses Cilium for ingress/L4-L7 networking and cert-manager for automated TLS certificates.

**Key Architecture Points:**
- **GitOps Workflow**: ArgoCD watches this repository and auto-syncs changes to the cluster
- **Multi-Environment**: Supports dev (ghost-dev namespace) and prod (ghost-prod namespace) via Kustomize overlays
- **Ingress**: Uses Cilium ingress controller (not Traefik) with shared LoadBalancer IP (10.10.10.200)
- **TLS**: cert-manager with Let's Encrypt production issuer for automatic certificate provisioning
- **Storage**: local-path storage class (K3s default) for Ghost content (20Gi) and MySQL (10Gi)
- **Secrets**: Sealed Secrets (kubeseal) for encrypted credentials - never commit plain secrets

## Common Commands

### Development & Deployment
```bash
# Install/upgrade Ghost deployment
make install                    # Apply ArgoCD Application manifest
make sync                       # Force ArgoCD to sync immediately

# Preview changes before applying
make diff-preview              # Preview dev environment changes
make diff-production           # Preview production environment changes

# Deploy to specific environments
make install-dev               # Deploy to dev namespace
make install-prod              # Deploy to production namespace

# Validate manifests
make validate                   # Dry-run kubectl apply
make lint                       # Lint Helm chart
```

### Operations & Troubleshooting
```bash
# Check status
make status                     # Show all resources in ghost namespace
argocd app get ghost           # Check ArgoCD application health

# View logs
make logs                       # Ghost application logs
make logs-mysql                 # MySQL database logs

# Testing
make test                       # Basic connectivity tests
make test-verbose               # Comprehensive deployment tests

# Backup
# MySQL backup:
kubectl exec -n ghost -it $(kubectl get pod -n ghost -l app.kubernetes.io/name=mysql -o jsonpath='{.items[0].metadata.name}') -- mysqldump -u root -p ghost > ghost-backup.sql

# Ghost content backup:
kubectl exec -n ghost -it $(kubectl get pod -n ghost -l app.kubernetes.io/name=ghost -o jsonpath='{.items[0].metadata.name}') -- tar czf /tmp/ghost-content-backup.tar.gz /var/lib/ghost/content
kubectl cp ghost/$(kubectl get pod -n ghost -l app.kubernetes.io/name=ghost -o jsonpath='{.items[0].metadata.name}'):/tmp/ghost-content-backup.tar.gz ./ghost-content-backup.tar.gz
```

### Secrets Management
```bash
# Create sealed secrets from .env.local
make secrets-create            # Generates k8s/base/ghost-sealed-secrets.yaml

# Template required:
cp .env.template .env.local   # Edit with actual values first
```

### Version Management
```bash
make version                   # Show current version
make bump-patch               # Bump patch version (1.0.0 -> 1.0.1)
make bump-minor               # Bump minor version (1.0.0 -> 1.1.0)
make bump-major               # Bump major version (1.0.0 -> 2.0.0)
make tag                      # Create and push git tag
```

## Code Architecture

### Directory Structure
```
k8s/
├── base/                      # Base configuration (production defaults)
│   ├── kustomization.yaml     # Kustomize base manifest
│   ├── argocd-application.yaml # ArgoCD Application resource
│   ├── helm-values.yaml        # Helm chart values (Bitnami Ghost)
│   ├── ghost-deployment.yaml   # Ghost deployment specs
│   ├── mysql-deployment.yaml   # MySQL deployment specs
│   ├── ghost-service.yaml      # ClusterIP service
│   ├── ghost-ingress.yaml      # Cilium ingress with TLS
│   ├── ghost-sealed-secrets.yaml # Encrypted secrets (kubeseal)
│   └── ghost-secrets.yaml      # Plain secrets template (git-ignored)
└── overlays/
    ├── dev/                    # Development environment overlay
    │   ├── kustomization.yaml  # Namespace: ghost-dev
    │   └── dev-values.yaml     # Dev-specific values (lower resources)
    └── prod/                   # Production environment overlay
        ├── kustomization.yaml  # Namespace: ghost-prod
        └── prod-values.yaml    # Prod-specific values (higher resources)
```

### Environment Differences

**Development (ghost-dev):**
- Hostname: dev-blog.shadyknollcave.io
- Resources: 250m-500m CPU, 256Mi-512Mi memory
- Storage: 20Gi Ghost, 10Gi MySQL

**Production (ghost-prod):**
- Hostname: blog.shadyknollcave.io
- Resources: 1000m-2000m CPU, 1Gi-2Gi memory
- Storage: 50Gi Ghost, 20Gi MySQL

### Deployment Architecture

The GitOps flow works as follows:
1. **Manifest Changes**: Commit changes to this repository (main branch)
2. **ArgoCD Detection**: ArgoCD detects the commit and compares desired vs. cluster state
3. **Auto-Sync**: If changes detected, ArgoCD automatically applies them (with self-heal)
4. **Health Checks**: ArgoCD waits for pods to be ready before marking healthy

**Critical Files:**
- `k8s/base/argocd-application.yaml`: Defines the ArgoCD Application that watches this repo
- `k8s/base/kustomization.yaml`: Lists all base resources to deploy
- `k8s/base/helm-values.yaml`: Helm chart values (Bitnami Ghost chart with MySQL)
- Overlays patch base values for environment-specific configuration

### Networking Flow

```
Internet (HTTPS:443)
    ↓
UDM Pro Port Forward: WAN:443 → 10.10.10.200:443
    ↓
Cilium LoadBalancer (10.10.10.200 - shared IP)
    ↓
Cilium Ingress (SNI-based hostname routing)
    ↓
Ghost Service (ClusterIP:80)
    ↓
Ghost Pods (Port:2368)
```

**Key Networking Details:**
- Cilium LoadBalancer IP pool: 10.10.10.200/29
- BGP advertises LoadBalancer IPs to router (AS65001 → AS65000)
- TLS termination happens at Cilium Ingress
- Backend services use ClusterIP

### Secrets Handling

**NEVER commit plain secrets.** Use this workflow:
1. Copy `.env.template` to `.env.local` (git-ignored)
2. Fill in actual values (passwords, emails, etc.)
3. Run `make secrets-create` to generate `ghost-sealed-secrets.yaml`
4. Commit the sealed secrets (encrypted with cluster public key)
5. Sealed Secrets controller decrypts on the cluster

**Required Secrets:**
- `ghost-password`: Ghost admin password
- `ghost-email`: Ghost admin email
- `mysql-root-password`: MySQL root password
- `mysql-password`: MySQL ghost user password

## Important Notes

### Git Workflow
- **Primary remote**: origin → git.shadyknollcave.io/micro/ghost-gitops.git
- **Backup remote**: backup → git@github.com:pedrof/ghost-gitops.git
- Always push to both remotes
- Use conventional commits: `feat:`, `fix:`, `chore:`, `docs:`

### Cluster Configuration
- **IngressClass**: cilium (NOT traefik)
- **StorageClass**: local-path (K3s default)
- **Certificate Issuer**: letsencrypt-prod (cert-manager ClusterIssuer)
- **LoadBalancer IPs**: Automatically allocated from 10.10.10.200/29 pool

### Helm Chart Configuration
- Chart: bitnami/ghost v20.1.3
- MySQL is enabled as a sub-chart
- Custom values in `k8s/base/helm-values.yaml`
- Environment-specific patches in overlays

### Common Issues

**ArgoCD not syncing:**
```bash
argocd app get ghost           # Check application status
argocd app sync ghost          # Force manual sync
kubectl logs -n argocd deployment/argocd-application-controller
```

**Certificate not provisioning:**
```bash
kubectl get certificaterequest -n ghost
kubectl describe clusterissuer letsencrypt-prod
kubectl logs -n cert-manager -l app=cert-manager
```

**Pods not starting:**
```bash
kubectl describe pod -n ghost
kubectl get pvc -n ghost       # Check PVC binding
```

**Ingress not accessible:**
```bash
kubectl get ingress -n ghost
cilium status                  # Check Cilium health
curl -v https://blog.shadyknollcave.io
```

## File References

- README.md: Comprehensive installation and usage documentation
- CHANGELOG.md: Version history and commit log
- VERSION: Current semantic version
- Makefile: All operational commands
- .env.template: Required environment variables template
