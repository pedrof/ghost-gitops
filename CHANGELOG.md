# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-01-24

### Added
- Initial GitOps repository setup for Ghost blog deployment
- ArgoCD Application manifest for Ghost deployment
- Kustomize configuration structure with base and overlays
- Development and production environment configurations
- MySQL database integration with Ghost
- Traefik ingress configuration with TLS support
- cert-manager integration for Let's Encrypt certificates
- Persistent volume configuration for Ghost and MySQL
- Resource limits and requests for production use
- Makefile with common operations (install, upgrade, logs, etc.)
- Comprehensive README.md with architecture and usage documentation
- Environment variable template (.env.template)
- Sealed secrets support for secure credential management
- Multi-environment support (dev/prod) with Kustomize overlays
- Git repository configuration with Gitea (primary) and GitHub (backup)

### Configuration
- Ghost Helm Chart: bitnami/ghost v20.1.3
- MySQL: Enabled and configured with persistent storage
- Ingress: Traefik with cert-manager TLS
- Storage: local-path storage class
- Resources: Configurable CPU and memory limits

[Unreleased]: https://git.shadyknollcave.io/micro/ghost-gitops/compare/v1.0.0...HEAD
[1.0.0]: https://git.shadyknollcave.io/micro/ghost-gitops/releases/tag/v1.0.0
