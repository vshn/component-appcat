###
### E2E Tests
### with KUTTL (https://kuttl.dev)
###

go_bin ?= $(PWD)/.work/bin
$(go_bin):
	@mkdir -p $@

kuttl_bin = $(go_bin)/kubectl-kuttl
$(kuttl_bin): export GOBIN = $(go_bin)
$(kuttl_bin): | $(go_bin)
	go install github.com/kudobuilder/kuttl/cmd/kubectl-kuttl@latest

.PHONY: e2e-test
e2e-test: $(kuttl_bin) ## Run e2e tests
	@kubectl create namespace appcat-e2e || true
	@kubectl label namespace appcat-e2e appuio.io/organization=vshn || true
	GOBIN=$(go_bin) $(kuttl_bin) test ./tests/e2e --config ./tests/e2e/kuttl-test.yaml --suppress-log=Events
	@rm -f kubeconfig
# kuttl leaves kubeconfig garbage: https://github.com/kudobuilder/kuttl/issues/297

.PHONY: run-single-e2e
run-single-e2e: $(kuttl_bin)
	@kubectl create namespace appcat-e2e || true
	@kubectl label namespace appcat-e2e appuio.io/organization=vshn || true
	GOBIN=$(go_bin) $(kuttl_bin) test ./tests/e2e --config ./tests/e2e/kuttl-test.yaml --suppress-log=Events --test $(test)
	@rm -f kubeconfig

.PHONY: .e2e-test-clean
.e2e-test-clean:
	@if [ -f $(KUBECONFIG) ]; then \
		kubectl delete mariadb --all; \
		kubectl delete jobs --all; \
		kubectl delete pods --all; \
	else \
		echo "no kubeconfig found"; \
	fi
	rm -f $(kuttl_bin)
