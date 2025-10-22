# Commodore Component: appcat

This is a [Commodore][commodore] Component for appcat.

This repository is part of Project Syn.
For documentation on Project Syn and this component, see https://syn.tools.

## Getting started for developers

This repository contains:

* `component`: SYN Commodore component for installing AppCat features

This component can be compiled with commodore like this:

```
$ commodore component compile . --search-paths . -n appcat -f tests/defaults.yml
#
# Alternative:
#
$ make test
```

The resulting compiled component can be found in `compiled/`.

There is currently no easy way to run it locally. You need to apply the compiled component to a test cluster to see if it works as expected.

This process is not suitable for installing the component on a production system.

## Use ArgoCD in kindev

Kindev provides a forgejo instance and ArgoCD that we can use the git repositories from it. ArgoCD is available at http://argocd.127.0.0.1.nip.io:8088/.

To push any of the golden tests you can use `make push-golden -e instance=vshn`, it will:
* Compile the given golden test
* Push it to forgejo
* Create or update an ArgoCD app according to the app config in the component

There's also a push target for the split setup: `make push-non-converged`, this will create two distinct apps on ArgoCD to deploy the respective parts to the right clusters.

There's a known issue:
On the very first sync after setting up kindev, ArgoCD doesn't recognize the `server-side` flag. Thus, the sync will fail. Simply click sync again in the ArgoCD GUI to trigger it again.

> **_NOTE:_** Even if kindev is started in the non-converged mode `make push-golden` will still work. It will simply ignore the vcluster and then behave like a normal converged setup.

## Splitted cluster configuration
In order to make the splitted cluster configuration work properly for development, you'll need to generate kubeconfigs.

There are two `make` targets in kindev that generate the correct kubeconfigs for you:

- `make vcluster-host-kubeconfig` -> This will print the kubeconfig and needs to go to `serviceClusterKubeconfigs` in `control-plane.yml`. Just replace the `dummy` string with the kubeconfig.
- `make vcluster-in-cluster-kubeconfig` -> This will print the kubeconfig that needs to go in `service-cluster.yml`. Same as above, the kubeconfig needs to be pasted in the `dummy` string in `controlPlaneKubeconfig`.

To deploy a service in the split configuration, make sure the claim contains the label `appcat.vshn.io/provider-config: kind`. Also make sure you're connected to the vcluster. It won't work if you're connected to the host kind cluster.

## ArgoCD SyncWaves

There's a postprocess function that will add ArgoCD syn annotations to each object of the given kind.
If any new types are introduced that need specific ordering, the `add_argo_annotations.jsonnet` is the right place.

## Debugging comp-functions locally

The golden targets `dev` and `control-plane` are pre-configured to support proxying the comp functions from Kind to the local endpoint.

To enable it, change these two parameters:
```yaml
  appcat:
    grpcEndpoint: host.docker.internal:9443
    proxyFunction: false
```

The `grpcEndpoint` depends on your docker implementation and should point to an address that's reachable from the containers.

```bash
HOSTIP=$(docker inspect kindev-control-plane | jq '.[0].NetworkSettings.Networks.kind.Gateway') # On kind MacOS/Windows
HOSTIP=host.docker.internal # On Docker Desktop distributions
HOSTIP=host.lima.internal # On Lima backed Docker distributions
Linux oneliner: echo `ip -4 addr show dev docker0 | grep inet | awk -F' ' '{print $2}' | awk -F'/' '{print $1}'`:9443
```

Also make sure that `facts.appcat_dev` is set on the target you want to proxy. This is a safeguard so we don't accidentally enable it on prod clusters.

## Kubeconfig Environment Variables in Kuttl E2E Tests

Our Kuttl E2E tests use a job-within-a-job pattern where tests run in two separate clusters:
- **control plane cluster** (where AppCat CRDs live)
- **service cluster** (where actual workloads run).

This requires careful handling of kubeconfig files to enable cross-cluster operations.

### Environment Variables

We use four environment variables to manage kubeconfigs:

### 1. `CONTROL_PLANE_KUBECONFIG_CONTENT` **mandatory** (base64-encoded)
- **Purpose**: Contains the entire control plane kubeconfig as a base64-encoded string
- **Why needed**: Can be injected as an environment variable into containers and scripts
- **Usage**: Scripts decode this to create `/tmp/control-plane-config`

### 2. `SERVICE_CLUSTER_KUBECONFIG_CONTENT` **mandatory** (base64-encoded)
- **Purpose**: Contains the entire service cluster kubeconfig as a base64-encoded string, equals to `CONTROL_PLANE_KUBECONFIG_CONTENT` in converged mode
- **Why needed**: Can be injected as an environment variable into containers and scripts
- **Usage**: Scripts decode this to create `/tmp/service-cluster-config`

### 3. `IN_CLUSTER_CONTROL_PLANE_KUBECONFIG` **optional** (file path)
- **Purpose**: Path to the kubeconfig file **as seen from within the control plane cluster**
- **Why needed**: Used to create Kubernetes secrets that mount the kubeconfig into pods
- **Example**: `/tmp/control-plane-config` or the original `~/.kube/config`

### 4. `IN_CLUSTER_SERVICE_CLUSTER_KUBECONFIG` **optional**  (file path)
- **Purpose**: Path to the kubeconfig file **as seen from within the service cluster**
- **Why needed**: Used to create Kubernetes secrets that mount the kubeconfig into pods
- **Example**: `/tmp/service-cluster-config` or the original `~/.kube/config`

## Documentation

The rendered documentation for this component is available on the [Commodore Components Hub](https://hub.syn.tools/appcat).

Documentation for this component is written using [Asciidoc][asciidoc] and [Antora][antora].
It's located in the [docs/](docs) folder.
The [Divio documentation structure](https://documentation.divio.com/) is used to organize its content.

Run the `make docs-serve` command in the root of the project, and then browse to http://localhost:2020 to see a preview of the current state of the documentation.

After writing the documentation, please use the `make lint_adoc` command and correct any warnings raised by the tool.

## Contributing and license

This library is licensed under [BSD-3-Clause](LICENSE).
For information about how to contribute see [CONTRIBUTING](CONTRIBUTING.md).

[commodore]: https://syn.tools/commodore/
[asciidoc]: https://asciidoctor.org/
[antora]: https://antora.org/
