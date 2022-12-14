MAKEFLAGS += --warn-undefined-variables
SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := all
.DELETE_ON_ERROR:
.SUFFIXES:

include Makefile.vars.mk
# Optional kind module
-include kind/kind.mk

-include apis/generate.mk

.PHONY: help
help: ## Show this help
	@grep -E -h '\s##\s' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = "(: ).*?## "}; {gsub(/\\:/,":", $$1)}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

.PHONY: lint_jsonnet
lint_jsonnet: ## Lint jsonnet files
	cd component && $(MAKE) $@

.PHONY: lint_yaml
lint_yaml: ## Lint yaml files
	$(YAMLLINT_DOCKER) -f parsable -c $(YAMLLINT_CONFIG) $(YAMLLINT_ARGS) -- .

.PHONY: lint_adoc
lint_adoc: ## Lint documentation
	$(VALE_CMD) $(VALE_ARGS)
.PHONY: lint_kubent
lint_kubent: ## Check for deprecated Kubernetes API versions
	$(KUBENT_DOCKER) $(KUBENT_ARGS) -f $(KUBENT_FILES)

.PHONY: git-diff
git-diff: ## Checks that there are no uncommitted changes
	@git diff --exit-code

.PHONY: docs-serve
docs-serve: ## Preview the documentation
	$(ANTORA_PREVIEW_CMD)

.PHONY: gen-golden-component
gen-golden-component:
	rm -rf component/tests/golden
	cd component && $(MAKE) gen-golden-all

.PHONY: gen-golden-packages
gen-golden-packages:
	rm -rf packages/tests/golden
	cd packages && $(MAKE) gen-golden-all

.PHONY: gen-golden-all
gen-golden-all: gen-golden-component gen-golden-packages ## For Renovate

.PHONY: clean
clean: kind-clean
clean:
	rm -rf .work
	make -C packages clean
	make -C component clean

