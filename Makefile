.PHONY: help install upgrade uninstall status diff validate lint test sync

VERSION := $(shell cat VERSION)
HELM_CHART := bitnami/ghost
HELM_VERSION := 20.1.3

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

install: ## Install Ghost using ArgoCD (sync application)
	kubectl apply -f k8s/base/argocd-application.yaml
	@echo "Waiting for ArgoCD to sync the application..."
	kubectl wait --for=condition=Available --timeout=300s -n argocd application/ghost || true

upgrade: ## Upgrade Ghost to the latest version
	helm upgrade ghost $(HELM_CHART) \
		--version $(HELM_VERSION) \
		--namespace ghost \
		--reuse-values \
		--wait \
		--timeout 10m

uninstall: ## Uninstall Ghost from the cluster
	kubectl delete -f k8s/base/argocd-application.yaml --ignore-not-found=true

status: ## Show the status of Ghost deployment
	kubectl get all -n ghost
	@echo "\n--- ArgoCD Application Status ---"
	kubectl get application ghost -n argocd -o jsonpath='{.status.healthStatus}' | jq -r '.[]'

diff: ## Show diff between live and desired state
	argocd app diff ghost

validate: ## Validate Kubernetes manifests
	kubectl apply --dry-run=client -f k8s/base/argocd-application.yaml

lint: ## Lint Helm chart
	helm lint $(HELM_CHART) --version $(HELM_VERSION)

test: ## Test the deployment
	@echo "Running basic connectivity tests..."
	@kubectl get pods -n ghost -l app.kubernetes.io/name=ghost
	@kubectl get ingress -n ghost
	@echo "\nFor detailed testing, run: make test-verbose"

test-verbose: ## Run verbose tests
	@echo "Checking Ghost pod readiness..."
	@kubectl wait --for=condition=ready --timeout=300s -n ghost pod -l app.kubernetes.io/name=ghost
	@echo "\nChecking service endpoints..."
	@kubectl get endpoints -n ghost
	@echo "\nChecking ingress configuration..."
	@kubectl describe ingress -n ghost
	@echo "\nAll tests passed!"

sync: ## Force sync ArgoCD application
	argocd app sync ghost
	argocd app wait ghost --health

logs: ## Show Ghost application logs
	kubectl logs -n ghost -l app.kubernetes.io/name=ghost --tail=100 -f

logs-mysql: ## Show MySQL logs
	kubectl logs -n ghost -l app.kubernetes.io/name=mysql --tail=100 -f

secrets-create: ## Create sealed secrets for sensitive values
	@echo "Creating sealed secrets..."
	@echo "Make sure you have kubeseal configured and the sealed-secret controller is running"
	@if [ -f .env.local ]; then \
		bash -c 'source .env.local && \
			kubectl create secret generic ghost-config \
				--from-literal=ghost-password=$$GHOST_PASSWORD \
				--from-literal=ghost-email=$$GHOST_EMAIL \
				--from-literal=mysql-username=$$MYSQL_USERNAME \
				--from-literal=mysql-password=$$MYSQL_PASSWORD \
				--from-literal=mysql-database=$$MYSQL_DATABASE \
				--from-literal=mysql-root-password=$$MYSQL_ROOT_PASSWORD \
				--from-literal=mail-user=$$MAIL_USER \
				--from-literal=mail-password=$$MAIL_PASSWORD \
				--from-literal=mail-host=$$MAIL_HOST \
				--namespace=ghost \
				--dry-run=client -o yaml | \
			kubeseal --format yaml > k8s/base/ghost-sealed-secrets.yaml'; \
		echo "Sealed secrets created at k8s/base/ghost-sealed-secrets.yaml"; \
	else \
		echo "ERROR: .env.local file not found. Copy .env.template to .env.local and fill in the values."; \
		exit 1; \
	fi

diff-preview: ## Preview changes for dev environment
	kubectl apply --dry-run=server -k k8s/overlays/dev

diff-production: ## Preview changes for prod environment
	kubectl apply --dry-run=server -k k8s/overlays/prod

install-dev: ## Install Ghost in development environment
	kubectl apply -k k8s/overlays/dev

install-prod: ## Install Ghost in production environment
	kubectl apply -k k8s/overlays/prod

version: ## Show version information
	@echo "Ghost GitOps Version: $(VERSION)"
	@echo "Helm Chart: $(HELM_CHART) Version: $(HELM_VERSION)"

bump-patch: ## Bump patch version
	@echo $$(($(shell cat VERSION | cut -d. -f3) + 1)) > VERSION
	$(eval NEW_VERSION := $(shell cat VERSION))
	@sed -i "s/^## \[Unreleased\]/## [Unreleased]\n\n## [$(NEW_VERSION)] - $$(date +%Y-%m-%d)/" CHANGELOG.md || true

bump-minor: ## Bump minor version
	@echo "$(shell cat VERSION | cut -d. -f1-2).$$(($(shell cat VERSION | cut -d. -f3) + 1))" > VERSION

bump-major: ## Bump major version
	@echo "$$(($(shell cat VERSION | cut -d. -f1) + 1)).0.0" > VERSION

tag: ## Create git tag for current version
	git tag -a v$(VERSION) -m "Release version $(VERSION)"
	git push origin v$(VERSION)
	git push backup v$(VERSION)
