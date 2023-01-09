# Commodore takes the root dir name as the package name
PACKAGE_NAME ?= $(shell basename ${PWD} | sed s/package-//)

root_volume     ?= -v "$${PWD}:/$(PACKAGE_NAME)"
commodore_args  ?= tests/$(instance).yml -v

ifneq "$(shell which docker 2>/dev/null)" ""
	DOCKER_CMD    ?= $(shell which docker)
	DOCKER_USERNS ?= ""
else
	DOCKER_CMD    ?= podman
	DOCKER_USERNS ?= keep-id
endif
DOCKER_ARGS ?= run --rm -u "$$(id -u):$$(id -g)" --userns=$(DOCKER_USERNS) -w /$(PACKAGE_NAME) -e HOME="/$(PACKAGE_NAME)"

COMMODORE_CMD  ?= $(DOCKER_CMD) $(DOCKER_ARGS) $(root_volume) docker.io/projectsyn/commodore:latest
COMPILE_CMD    ?= $(COMMODORE_CMD) package compile . $(commodore_args)

instance ?= provider-cloudscale
test_instances = $(shell find tests -maxdepth 1 -type f -name "*.yml")
