# Ghost Blog - GitOps Deployment

[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](VERSION)
[![ArgoCD](https://img.shields.io/badge/deployment-ArgoCD-green.svg)](https://argocd.shadyknollcave.io)

GitOps repository for deploying Ghost blogging platform on K3s Kubernetes cluster using ArgoCD.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Architecture](#architecture)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
- [Environments](#environments)
- [Secrets Management](#secrets-management)
- [Troubleshooting](#troubleshooting)
- [Development](#development)
- [Maintenance](#maintenance)

## Overview

This repository contains ArgoCD Application manifests and Kustomize configurations for deploying Ghost with MySQL backend on a K3s cluster via GitOps.

### Features

- **Automated Deployment**: ArgoCD syncs changes from this repository to the cluster
- **Helm Chart**: Uses official Bitnami Ghost Helm chart
- **MySQL Backend**: Includes MySQL database for persistent storage
- **TLS/SSL**: Automated certificate management via cert-manager with Let's Encrypt
- **Ingress**: Cilium ingress controller for external access and load balancing
- **Multi-Environment**: Support for dev and production environments
- **Resource Management**: Configurable CPU and memory limits
- **Persistent Storage**: Local-path storage for Ghost content and database

## Prerequisites

### Required Tools

- **kubectl** - Kubernetes CLI (configured for K3s cluster)
- **helm** - Helm package manager (v3+)
- **argocd** - ArgoCD CLI
- **kubeseal** - For sealed secrets management
- **kustomize** - Kubernetes manifest customization

### Cluster Requirements

- **Kubernetes**: K3s cluster running
- **Ingress Controller**: Cilium installed and configured with ingress support
- **Certificate Manager**: cert-manager installed with Let's Encrypt issuer
- **Storage**: local-path storage class available
- **ArgoCD**: Installed and accessible

### Initial Setup

1. Clone this repository:
   ```bash
   git clone https://git.shadyknollcave.io/micro/ghost-gitops.git
   cd ghost-gitops
   ```

2. Set up remote repositories:
   ```bash
   git remote set-url origin https://git.shadyknollcave.io/micro/ghost-gitops.git
   git remote set-url backup git@github.com:pedrof/ghost-gitops.git
   ```

3. Configure environment variables:
   ```bash
   cp .env.template .env.local
   # Edit .env.local with your actual values
   ```

## Architecture

```
┌─────────────────┐      ┌──────────────┐      ┌─────────────┐
│   ArgoCD        │──────▶│   Ghost     │─────▶│   MySQL     │
│   (GitOps)      │      │   (Blog)     │      │  (Database) │
└─────────────────┘      └──────────────┘      └─────────────┘
         │                        │
         │                        ▼
         │                ┌──────────────┐
         │                │   Cilium     │
         │                │  (Ingress)   │
         │                └──────────────┘
         │                        │
         ▼                        ▼
┌─────────────────┐      ┌──────────────┐
│   Git Repo      │      │  cert-manager│
│   (This Repo)   │      │   (TLS/SSL)  │
└─────────────────┘      └──────────────┘
```

### Components

- **Ghost**: Node.js blogging platform
- **MySQL**: Relational database for Ghost content
- **Cilium**: eBPF-based networking, security, and ingress controller
- **cert-manager**: Automatic TLS certificate management
- **ArgoCD**: Continuous deployment and GitOps operator
- **Local-Path**: K3s storage provisioner

## Installation

### Quick Start

Deploy Ghost to your K3s cluster:

```bash
# Apply the ArgoCD Application manifest
make install

# Or manually:
kubectl apply -f k8s/base/argocd-application.yaml
```

### Verify Deployment

```bash
# Check deployment status
make status

# Watch the pods
kubectl get pods -n ghost -w

# Check ArgoCD application
argocd app get ghost
```

### Access Ghost

Once deployed, Ghost will be available at:
- **Production**: https://blog.shadyknollcave.io
- **Development**: https://dev-blog.shadyknollcave.io

Access the Ghost admin panel at `https://blog.shadyknollcave.io/ghost`

## Configuration

### Environment Variables

Key configuration options (see `.env.template`):

| Variable | Description | Default |
|----------|-------------|---------|
| `GHOST_HOST` | Ghost hostname | blog.shadyknollcave.io |
| `GHOST_USERNAME` | Admin username | admin |
| `GHOST_PASSWORD` | Admin password | *required* |
| `GHOST_EMAIL` | Admin email | *required* |
| `MYSQL_ROOT_PASSWORD` | MySQL root password | *required* |
| `MYSQL_PASSWORD` | MySQL user password | *required* |

### Helm Values

The Helm values are configured in `k8s/base/argocd-application.yaml`. Key settings:

```yaml
ghostHost: blog.shadyknollcave.io
ingress:
  enabled: true
  className: cilium
  hostname: blog.shadyknollcave.io
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    cilium.io/ingress-class: cilium
    cilium.io/service-type: LoadBalancer
persistence:
  enabled: true
  storageClass: local-path
  size: 20Gi
mysql:
  enabled: true
  primary:
    persistence:
      size: 10Gi
```

## Usage

### Common Commands

```bash
# Show all available commands
make help

# Install Ghost
make install

# Uninstall Ghost
make uninstall

# View status
make status

# View logs
make logs

# Sync ArgoCD application
make sync
```

### Updating Ghost

To update Ghost to a new version:

1. Update the Helm chart version in `k8s/base/argocd-application.yaml`
2. Commit and push the changes
3. ArgoCD will automatically detect and apply the update

```bash
# Manual sync if needed
argocd app sync ghost
argocd app wait ghost --health
```

## Environments

This repository supports multiple environments using Kustomize overlays:

### Base Configuration (`k8s/base/`)

Contains the base ArgoCD Application manifest and common settings.

### Development Environment (`k8s/overlays/dev/`)

- Hostname: `dev-blog.shadyknollcave.io`
- Namespace: `ghost-dev`
- Lower resource limits (500m CPU, 512Mi memory)
- Smaller storage sizes

### Production Environment (`k8s/overlays/prod/`)

- Hostname: `blog.shadyknollcave.io`
- Namespace: `ghost-prod`
- Higher resource limits (2000m CPU, 2Gi memory)
- Larger storage sizes (50Gi Ghost, 20Gi MySQL)

### Deploy to Different Environments

```bash
# Preview dev changes
make diff-preview

# Deploy to dev
make install-dev

# Preview production changes
make diff-production

# Deploy to production
make install-prod
```

## Secrets Management

**IMPORTANT**: Never commit actual secrets to this repository!

### Create Sealed Secrets

Use `kubeseal` to create encrypted secrets:

```bash
# Copy the template
cp .env.template .env.local

# Edit with actual values
nano .env.local

# Create sealed secrets
make secrets-create
```

This creates `k8s/base/ghost-sealed-secrets.yaml` which can be safely committed.

### Sealed Secrets in Use

The sealed secrets should be referenced in the ArgoCD Application:

```yaml
spec:
  source:
    helm:
      parameters:
        - name: ghostPassword
          valueFrom:
            secretKeyRef:
              name: ghost-config
              key: ghost-password
```

## Troubleshooting

### Common Issues

**Pod not starting:**
```bash
# Check pod status
kubectl describe pod -n ghost

# Check logs
make logs
make logs-mysql
```

**Ingress not working:**
```bash
# Check ingress configuration
kubectl describe ingress -n ghost

# Verify Cilium is running
kubectl get pods -n kube-system -l app.kubernetes.io/name=cilium-agent

# Check Cilium ingress status
cilium status
```

**Certificate issues:**
```bash
# Check cert-manager
kubectl get certificaterequest -n ghost

# Check ClusterIssuer
kubectl get clusterissuer letsencrypt-prod
```

**ArgoCD sync issues:**
```bash
# Check application status
argocd app get ghost

# Force sync
argocd app sync ghost --hard-refresh

# Check ArgoCD logs
kubectl logs -n argocd deployment/argocd-application-controller
```

### Health Checks

```bash
# Run comprehensive tests
make test-verbose

# Check Ghost is responding
curl -I https://blog.shadyknollcave.io

# Check MySQL connectivity
kubectl exec -n ghost -it \
  $(kubectl get pod -n ghost -l app.kubernetes.io/name=ghost -o jsonpath='{.items[0].metadata.name}') \
  -- nc -zv localhost 3306
```

## Development

### Project Structure

```
ghost-gitops/
├── k8s/
│   ├── base/
│   │   ├── kustomization.yaml
│   │   └── argocd-application.yaml
│   └── overlays/
│       ├── dev/
│       │   ├── kustomization.yaml
│       │   └── dev-values.yaml
│       └── prod/
│           ├── kustomization.yaml
│           └── prod-values.yaml
├── .env.template          # Environment variables template
├── .gitignore            # Git ignore rules
├── Makefile              # Common tasks
├── VERSION               # Current version
├── CHANGELOG.md          # Version history
└── README.md             # This file
```

### Making Changes

1. Make your changes to the manifests
2. Test locally with `make diff-preview`
3. Commit with conventional commit message
4. Push to repository
5. ArgoCD will automatically sync changes

```bash
# Example workflow
git checkout -b feature/add-metrics
# Make changes
make diff-preview
git add k8s/
git commit -m "feat: add Prometheus metrics to Ghost deployment"
git push origin feature/add-metrics
# Create PR, merge to main
```

## Maintenance

### Version Management

```bash
# Bump version
make bump-patch  # or bump-minor, bump-major

# Create git tag
make tag

# View version
make version
```

### Backup

**MySQL Backup:**
```bash
kubectl exec -n ghost -it \
  $(kubectl get pod -n ghost -l app.kubernetes.io/name=mysql -o jsonpath='{.items[0].metadata.name}') \
  -- mysqldump -u root -p ghost > ghost-backup.sql
```

**Ghost Content Backup:**
```bash
kubectl exec -n ghost -it \
  $(kubectl get pod -n ghost -l app.kubernetes.io/name=ghost -o jsonpath='{.items[0].metadata.name}') \
  -- tar czf /tmp/ghost-content-backup.tar.gz /var/lib/ghost/content
kubectl cp ghost/$(kubectl get pod -n ghost -l app.kubernetes.io/name=ghost -o jsonpath='{.items[0].metadata.name}'):/tmp/ghost-content-backup.tar.gz ./ghost-content-backup.tar.gz
```

### Monitoring

Set up monitoring for production:

```bash
# Check resource usage
kubectl top pods -n ghost
kubectl top nodes

# Check persistent volumes
kubectl get pv -n ghost
kubectl get pvc -n ghost
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

MIT License - see LICENSE file for details

## Support

For issues and questions:
- Create an issue in the repository
- Contact: Pedro Fernandez <microreal@shadyknollcave.io>

## References

- [Ghost Documentation](https://docs.ghost.org/)
- [Bitnami Ghost Helm Chart](https://github.com/bitnami/charts/tree/main/bitnami/ghost)
- [ArgoCD Documentation](https://argoproj.github.io/argo-cd/)
- [K3s Documentation](https://docs.k3s.io/)
- [Cilium Documentation](https://docs.cilium.io/)
- [cert-manager Documentation](https://cert-manager.io/docs/)
