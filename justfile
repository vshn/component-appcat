# component-appcat justfile

COMPONENT_NAME := "appcat"

# Default recipe to display help
default:
    @just --list

# Show this help
help:
    @just --list

# All-in-one linting
all: lint

# All-in-one linting
lint: lint-jsonnet lint-yaml lint-adoc lint-kubent

# Lint jsonnet files
lint-jsonnet:
    #!/usr/bin/env bash
    set -euo pipefail
    DOCKER_CMD=$(command -v docker || echo podman)
    JSONNET_FILES=$(find . -type f -not -path './vendor/*' \( -name '*.*jsonnet' -o -name '*.libsonnet' \))
    if [ -n "$JSONNET_FILES" ]; then
        $DOCKER_CMD run --rm -u $(id -u):$(id -g) -v "${PWD}:/{{COMPONENT_NAME}}" -w /{{COMPONENT_NAME}} \
            --entrypoint=jsonnetfmt docker.io/bitnamilegacy/jsonnet:latest \
            --in-place --pad-arrays --test -- $JSONNET_FILES
    fi

# Lint yaml files
lint-yaml:
    #!/usr/bin/env bash
    set -euo pipefail
    DOCKER_CMD=$(command -v docker || echo podman)
    $DOCKER_CMD run --rm -u $(id -u):$(id -g) -v "${PWD}:/{{COMPONENT_NAME}}" -w /{{COMPONENT_NAME}} \
        docker.io/cytopia/yamllint:latest \
        -f parsable -c .yamllint.yml --no-warnings -- .

# Lint documentation
lint-adoc:
    #!/usr/bin/env bash
    set -euo pipefail
    DOCKER_CMD=$(command -v docker || echo podman)
    $DOCKER_CMD run --rm -u $(id -u):$(id -g) -v "${PWD}:/{{COMPONENT_NAME}}" -w /{{COMPONENT_NAME}} \
        --volume "${PWD}/docs/modules:/pages" ghcr.io/vshn/vale:2.15.5 \
        --minAlertLevel=error --config=/pages/ROOT/pages/.vale.ini /pages

# Lint deprecated Kubernetes API versions
lint-kubent instance="defaults":
    #!/usr/bin/env bash
    set -euo pipefail
    DOCKER_CMD=$(command -v docker || echo podman)
    GOLDEN_FILES=$(find tests/golden/{{instance}} -type f 2>/dev/null || echo "")
    KUBENT_FILES=$(echo "$GOLDEN_FILES" | sed 's/ /,/g')
    if [ -n "$KUBENT_FILES" ]; then
        $DOCKER_CMD run --rm -u $(id -u):$(id -g) -v "${PWD}:/{{COMPONENT_NAME}}" -w /{{COMPONENT_NAME}} \
            --entrypoint=/app/kubent ghcr.io/doitintl/kube-no-trouble:latest \
            -c=false --helm3=false -e -f $KUBENT_FILES
    fi

# All-in-one formatting
format: format-jsonnet

# Format jsonnet files
format-jsonnet:
    #!/usr/bin/env bash
    set -euo pipefail
    DOCKER_CMD=$(command -v docker || echo podman)
    JSONNET_FILES=$(find . -type f -not -path './vendor/*' \( -name '*.*jsonnet' -o -name '*.libsonnet' \))
    if [ -n "$JSONNET_FILES" ]; then
        $DOCKER_CMD run --rm -u $(id -u):$(id -g) -v "${PWD}:/{{COMPONENT_NAME}}" -w /{{COMPONENT_NAME}} \
            --entrypoint=jsonnetfmt docker.io/bitnamilegacy/jsonnet:latest \
            --in-place --pad-arrays -- $JSONNET_FILES
    fi

# Preview the documentation
docs-serve:
    #!/usr/bin/env bash
    set -euo pipefail
    DOCKER_CMD=$(command -v docker || echo podman)
    git_dir=$(git rev-parse --git-common-dir)
    if [ "$git_dir" != ".git" ]; then
        antora_git_volume="-v ${git_dir}:/preview/antora/.git:ro"
    else
        antora_git_volume="-v ${PWD}/.git:/preview/antora/.git:ro"
    fi
    $DOCKER_CMD run --rm --publish 35729:35729 --publish 2020:2020 \
        $antora_git_volume --volume "${PWD}/docs:/preview/antora/docs" \
        ghcr.io/vshn/antora-preview:3.1.4 --style=syn --antora=docs

# Compile the component
compile:
    #!/usr/bin/env bash
    set -euox pipefail
    DOCKER_CMD=$(command -v docker || echo podman)
    default_args="--search-paths ./dependencies --search-paths . -n {{COMPONENT_NAME}}"
    commodore_args="${commodore_args:-} ${default_args}"
    mkdir -p dependencies
    $DOCKER_CMD run --rm -u $(id -u):$(id -g) -v "${PWD}:/{{COMPONENT_NAME}}" -w /{{COMPONENT_NAME}} \
        -e HOME="/{{COMPONENT_NAME}}" docker.io/projectsyn/commodore:v1.29.0 \
        component compile . $commodore_args

# Compile the component with instance parameter
test instance:
    #!/usr/bin/env bash
    set -euo pipefail
    export commodore_args="-f tests/{{instance}}.yml"
    just compile

# Update the reference version for target `golden-diff`
gen-golden instance:
    #!/usr/bin/env bash
    set -euo pipefail
    export commodore_args="-f tests/{{instance}}.yml"
    just clean
    just compile
    rm -rf tests/golden/{{instance}}
    mkdir -p tests/golden/{{instance}}
    cp -R compiled/. tests/golden/{{instance}}/.

# Diff compile output against the reference version. Review output and run `just gen-golden instance` and `just golden-diff instance` if this target fails
golden-diff instance:
    #!/usr/bin/env bash
    set -euo pipefail
    export commodore_args="-f tests/{{instance}}.yml"
    just clean
    just compile
    git diff --exit-code --minimal --no-index -- tests/golden/{{instance}} compiled/

# Clean the project
clean:
    rm -rf .cache compiled dependencies vendor helmcharts jsonnetfile*.json || true

# Install pre-commit hook in .git/hooks
pre-commit-hook:
    /usr/bin/cp -fa .githooks/pre-commit .git/hooks/pre-commit

# Push the target instance to the local forgejo instance, so it can be applied by argocd
push-golden instance="dev" repo="appcat" cluster="https://kubernetes.default.svc":
    #!/usr/bin/env bash
    set -euox pipefail
    export commodore_args="-f tests/{{instance}}.yml"
    just clean
    just gen-golden {{instance}}
    cd tests/golden/{{instance}}/appcat/appcat
    git init --initial-branch=master
    git config user.email "devcontainer@local.dev"
    git config user.name "DevContainer User"
    git add .
    git commit -m "update"
    git remote add origin http://gitea_admin:adminadmin@forgejo.127.0.0.1.nip.io:8088/gitea_admin/{{repo}}.git
    git push -u origin master --force
    rm -rf .git
    cd -
    yq eval-all '. as $item ireduce ({}; . * $item )' hack/base_app.yaml tests/golden/{{instance}}/appcat/apps/appcat.yaml \
    | yq '.metadata.name = "{{instance}}"' | yq '.spec.source.repoURL = "http://forgejo-http.forgejo.svc:3000/gitea_admin/{{repo}}"' \
    | yq '.spec.destination.server = "{{cluster}}"' | kubectl apply -f -

# Run e2e tests with KUTTL
e2e-test:
    #!/usr/bin/env bash
    set -euo pipefail
    go_bin=$(pwd)/.work/bin
    mkdir -p $go_bin
    if [ ! -f $go_bin/kubectl-kuttl ]; then
        GOBIN=$go_bin go install github.com/kudobuilder/kuttl/cmd/kubectl-kuttl@latest
    fi
    kubectl create namespace appcat-e2e || true
    kubectl label namespace appcat-e2e appuio.io/organization=vshn || true
    GOBIN=$go_bin $go_bin/kubectl-kuttl test ./tests/e2e --config ./tests/e2e/kuttl-test.yaml --suppress-log=Events
    rm -f kubeconfig

# Run single e2e test
run-single-e2e test:
    #!/usr/bin/env bash
    set -euo pipefail
    go_bin=$(pwd)/.work/bin
    mkdir -p $go_bin
    if [ ! -f $go_bin/kubectl-kuttl ]; then
        GOBIN=$go_bin go install github.com/kudobuilder/kuttl/cmd/kubectl-kuttl@latest
    fi
    kubectl create namespace appcat-e2e || true
    kubectl label namespace appcat-e2e appuio.io/organization=vshn || true
    GOBIN=$go_bin $go_bin/kubectl-kuttl test ./tests/e2e --config ./tests/e2e/kuttl-test.yaml --suppress-log=Events --test {{test}}
    rm -f kubeconfig
