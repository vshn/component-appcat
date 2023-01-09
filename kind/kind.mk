kind_dir ?= $(PWD)/.kind
kind_bin = $(go_bin)/kind

# Prepare kind binary
$(kind_bin): export GOOS = $(shell go env GOOS)
$(kind_bin): export GOARCH = $(shell go env GOARCH)
$(kind_bin): export GOBIN = $(go_bin)
$(kind_bin): | $(go_bin)
	go install sigs.k8s.io/kind@latest

.PHONY: kind
kind: export KUBECONFIG = $(KIND_KUBECONFIG)
kind: kind-setup-ingress

.PHONY: kind-setup
kind-setup: export KUBECONFIG = $(KIND_KUBECONFIG)
kind-setup: $(KIND_KUBECONFIG) ## Creates the kind cluster

.PHONY: kind-setup-ingress
kind-setup-ingress: export KUBECONFIG = $(KIND_KUBECONFIG)
kind-setup-ingress: kind-setup ## Install NGINX as ingress controller onto kind cluster (localhost:8081)
	kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

.PHONY: kind-clean
kind-clean: export KUBECONFIG = $(KIND_KUBECONFIG)
kind-clean: ## Removes the kind Cluster
	@$(kind_bin) delete cluster --name $(KIND_CLUSTER) || true
	rm -rf $(kind_dir) $(kind_bin)

.PHONY: kind-install-crossplane
kind-install-crossplane:
	kubectl create namespace crossplane-system
	helm repo add crossplane-stable https://charts.crossplane.io/stable
	helm repo update
	helm install crossplane --namespace crossplane-system crossplane-stable/crossplane
	kubectl wait -n crossplane-system deployment crossplane --for=condition=Available

.PHONY: kind-install-provider-kubernetes
kind-install-provider-kubernetes:
	kubectl crossplane install provider crossplane/provider-kubernetes:main
	kubectl wait --for condition=Healthy provider.pkg.crossplane.io/crossplane-provider-kubernetes --timeout 60s
	kubectl create clusterrolebinding crossplane:provider-kubernetes-admin --clusterrole cluster-admin --serviceaccount crossplane-system:$$(kubectl get sa -n crossplane-system -o custom-columns=NAME:.metadata.name --no-headers | grep provider-kubernetes)
.PHONY: kind-install-provider-stackgres
kind-install-provider-stackgres:
	kubectl apply -f https://stackgres.io/downloads/stackgres-k8s/stackgres/1.4.0/stackgres-operator-demo.yml
	kubectl wait -n stackgres deployment -l group=stackgres.io --for=condition=Available
	kubectl get pods -n stackgres -l group=stackgres.io

.PHONY: kind-all
kind-all: kind kind-install-crossplane kind-install-provider-kubernetes kind-install-provider-stackgres

$(KIND_KUBECONFIG): export KUBECONFIG = $(KIND_KUBECONFIG)
$(KIND_KUBECONFIG): $(kind_bin)
	$(kind_bin) create cluster \
		--name $(KIND_CLUSTER) \
		--image $(KIND_IMAGE) \
		--config kind/config.yaml
	@kubectl version
	@kubectl cluster-info
	@kubectl config use-context kind-$(KIND_CLUSTER)
	@echo =======
	@echo "Setup finished. To interact with the local dev cluster, set the KUBECONFIG environment variable as follows:"
	@echo "export KUBECONFIG=$$(realpath "$(KIND_KUBECONFIG)")"
	@echo =======
