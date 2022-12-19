# Commodore takes the root dir name as the component name
COMPONENT_NAME ?= appcat
COMPONENT_SUBDIR ?= $(shell basename ${PWD})

compiled_path   ?= compiled/$(COMPONENT_NAME)/$(COMPONENT_NAME)
root_volume     ?= -v "$${PWD}/../:/$(COMPONENT_NAME)"
compiled_volume ?= -v "$${PWD}/$(compiled_path):/$(COMPONENT_NAME)"
commodore_args  ?= --search-paths . -n $(COMPONENT_NAME)

ifneq "$(shell which docker 2>/dev/null)" ""
	DOCKER_CMD    ?= $(shell which docker)
	DOCKER_USERNS ?= ""
else
	DOCKER_CMD    ?= podman
	DOCKER_USERNS ?= keep-id
endif
DOCKER_ARGS ?= run --rm -u "$$(id -u):$$(id -g)" --userns=$(DOCKER_USERNS) -w /$(COMPONENT_NAME)/$(COMPONENT_SUBDIR) -e HOME="/$(COMPONENT_NAME)"

JSONNET_FILES   ?= $(shell find . -type f -not -path './vendor/*' \( -name '*.*jsonnet' -or -name '*.libsonnet' \))
JSONNETFMT_ARGS ?= --in-place --pad-arrays
JSONNET_IMAGE   ?= docker.io/bitnami/jsonnet:latest
JSONNET_DOCKER  ?= $(DOCKER_CMD) $(DOCKER_ARGS) $(root_volume) --entrypoint=jsonnetfmt $(JSONNET_IMAGE)

COMMODORE_CMD  ?= $(DOCKER_CMD) $(DOCKER_ARGS) $(root_volume) docker.io/projectsyn/commodore:latest
COMPILE_CMD    ?= $(COMMODORE_CMD) component compile . $(commodore_args)
JB_CMD         ?= $(DOCKER_CMD) $(DOCKER_ARGS) --entrypoint /usr/local/bin/jb docker.io/projectsyn/commodore:latest install
GOLDEN_FILES    ?= $(shell find tests/golden/$(instance) -type f)

instance ?= defaults
test_instances = tests/defaults.yml tests/cloudscale.yml tests/exoscale.yml
