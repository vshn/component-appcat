MAKEFLAGS += --warn-undefined-variables
SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := all
.DELETE_ON_ERROR:
.SUFFIXES:

include Makefile.vars.mk
include docs/antora-preview.mk

# testing
include tests/tests.mk

.PHONY: all
all: help

.PHONY: help
help: ## Show this help
	@grep -E -h '\s##\s' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = "(: ).*?## "}; {gsub(/\\:/,":", $$1)}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

.PHONY: all
all: lint

.PHONY: lint
lint: lint_jsonnet lint_yaml lint_adoc lint_kubent ## All-in-one linting

.PHONY: lint_jsonnet
lint_jsonnet: $(JSONNET_FILES) ## Lint jsonnet files
	$(JSONNET_DOCKER) $(JSONNETFMT_ARGS) --test -- $?

.PHONY: lint_yaml
lint_yaml: ## Lint yaml files
	$(YAMLLINT_DOCKER) -f parsable -c $(YAMLLINT_CONFIG) $(YAMLLINT_ARGS) -- .

.PHONY: lint_adoc
lint_adoc: ## Lint documentation
	$(VALE_CMD) $(VALE_ARGS)

.PHONY: lint_kubent
lint_kubent: ## Lint deprecated Kubernetes API versions
	$(KUBENT_DOCKER) $(KUBENT_ARGS) -f $(KUBENT_FILES)

.PHONY: format
format: format_jsonnet ## All-in-one formatting

.PHONY: format_jsonnet
format_jsonnet: $(JSONNET_FILES) ## Format jsonnet files
	$(JSONNET_DOCKER) $(JSONNETFMT_ARGS) -- $?

.PHONY: docs-serve
docs-serve: ## Preview the documentation
	$(ANTORA_PREVIEW_CMD)

.PHONY: compile
.compile:
	mkdir -p dependencies
	$(COMPILE_CMD)

.PHONY: test pre-commit-hook
test: commodore_args += -f tests/$(instance).yml
test: .compile ## Compile the component
.PHONY: gen-golden
gen-golden: commodore_args += -f tests/$(instance).yml
gen-golden: clean .compile ## Update the reference version for target `golden-diff`.
	@rm -rf tests/golden/$(instance)
	@mkdir -p tests/golden/$(instance)
	@cp -R compiled/. tests/golden/$(instance)/.

.PHONY: golden-diff
golden-diff: commodore_args += -f tests/$(instance).yml
golden-diff: clean .compile ## Diff compile output against the reference version. Review output and run `make gen-golden golden-diff` if this target fails.
	@git diff --exit-code --minimal --no-index -- tests/golden/$(instance) compiled/

.PHONY: golden-diff-all
golden-diff-all: recursive_target=golden-diff pre-commit-hook
golden-diff-all: $(test_instances) ## Run golden-diff for all instances. Note: this doesn't work when running make with multiple parallel jobs (-j != 1).

.PHONY: gen-golden-all
gen-golden-all: recursive_target=gen-golden
gen-golden-all: $(test_instances) ## Run gen-golden for all instances. Note: this doesn't work when running make with multiple parallel jobs (-j != 1).

.PHONY: lint_kubent_all
lint_kubent_all: recursive_target=lint_kubent
lint_kubent_all: $(test_instances) ## Lint deprecated Kubernetes API versions for all golden test instances. Will exit on first error. Note: this doesn't work when running make with multiple parallel jobs (-j != 1).

.PHONY: $(test_instances)
$(test_instances):
	$(MAKE) $(recursive_target) -e instance=$(basename $(@F))

.PHONY: clean
clean: ## Clean the project
	rm -rf .cache compiled dependencies vendor helmcharts jsonnetfile*.json || true


.PHONY: pre-commit-hook
pre-commit-hook: ## Install pre-commit hook in .git/hooks
	/usr/bin/cp -fa .githooks/pre-commit .git/hooks/pre-commit

.PHONY: push-golden
instance=dev
repo=appcat
cluster=https://kubernetes.default.svc
push-golden: commodore_args += -f tests/$(instance).yml
push-golden: clean gen-golden ## Push the target instance to the local forgejo instance, so it can be applied by argocd
	cd tests/golden/$(instance)/appcat/appcat && \
	git init --initial-branch=master && \
	git config user.email "devcontainer@local.dev" && \
	git config user.name "DevContainer User" && \
	git add . && \
	git commit -m "update" && \
	git remote add origin http://gitea_admin:adminadmin@forgejo.127.0.0.1.nip.io:8088/gitea_admin/$(repo).git && \
	git push -u origin master --force && \
	rm -rf .git
	yq eval-all '. as $$item ireduce ({}; . * $$item )' hack/base_app.yaml tests/golden/$(instance)/appcat/apps/appcat.yaml \
	| yq '.metadata.name = "$(instance)"' | yq '.spec.source.repoURL = "http://forgejo-http.forgejo.svc:3000/gitea_admin/$(repo)"' \
	| yq '.spec.destination.server = "$(cluster)"' | kubectl apply -f -

.PHONY: push-non-converged
push-non-converged: ## This pushes the configuration for a split setup to argocd
	$(MAKE) push-golden -e instance=service-cluster -e repo=service-cluster
	$(MAKE) push-golden -e instance=control-plane -e repo=control-plane cluster=https://controlplane.vcluster.svc
