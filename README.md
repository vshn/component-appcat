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
