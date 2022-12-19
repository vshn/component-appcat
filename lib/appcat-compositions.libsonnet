local fromCompositeFieldPath(from, to) = {
  // this is the default patch type
  // This type patches from a field within the XR to a field within the composed resource.
  // It’s commonly used to expose a composed resource spec field as an XR spec field.
  type: 'FromCompositeFieldPath',
  fromFieldPath: from,
  toFieldPath: to,
};

local toCompositeFieldPath(from, to) = {
  //  This type patches from a field within the composed resource to a field within the XR.
  // It’s commonly used to derive an XR status field from a composed resource status field.
  type: 'ToCompositeFieldPath',
  fromFieldPath: from,
  toFieldPath: to,
};

local availablePatchSets = {
  annotations: {
    patches: [
      fromCompositeFieldPath('metadata.annotations', 'metadata.annotations'),
    ],
  },
  labels: {
    patches: [
      fromCompositeFieldPath('metadata.labels', 'metadata.labels'),
    ],
  },
};

local patchSetRef(name) = {
  type: 'PatchSet',
  patchSetName: name,
};

local commonResources = {
  observeClaimNamespace: {
    // This resource "observes" the namespace of the Claim.
    // It can be used to copy labels and annotations from the namespace to the composition.
    // Requirements: provider-kubernetes (https://github.com/crossplane-contrib/provider-kubernetes)
    base: {
      apiVersion: 'kubernetes.crossplane.io/v1alpha1',
      kind: 'Object',
      spec: {
        managementPolicy: 'Observe',
        forProvider: {
          manifest: {
            apiVersion: 'v1',
            kind: 'Namespace',
            metadata: {
              name: '',  // patched at runtime
            },
          },
        },
        providerConfigRef: {
          name: 'kubernetes',
        },
      },
    },
    patches: [
      fromCompositeFieldPath(from='metadata.labels[crossplane.io/claim-namespace]', to='spec.forProvider.manifest.metadata.name'),
      toCompositeFieldPath(from='status.atProvider.manifest.metadata.labels[appuio.io/organization]', to='metadata.labels[appuio.io/organization]'),
      fromCompositeFieldPath(from='metadata.labels[crossplane.io/composite]', to='metadata.name') + {
        transforms: [ {
          type: 'string',
          string: { fmt: '%s-ns-observer', type: 'Format' },
        } ],
      },
    ],

  },
};


local compositeRef(xrd, version='') = {
  apiVersion: '%s/%s' % [
    xrd.spec.group,
    if version == '' then xrd.spec.versions[0].name else version,
  ],
  kind: xrd.spec.names.kind,
};

local connFromSecretKey(name, from=name) = {
  name: name,
  fromConnectionSecretKey: from,
  type: 'FromConnectionSecretKey',
};
local connFromFieldPath(name, field) = {
  fromFieldPath: field,
  type: 'FromFieldPath',
  name: name,
};

{
  PatchSet(name):
    assert std.objectHas(availablePatchSets, name) : "common patch set '%s' doesn't exist" % name;
    availablePatchSets[name] { name: name },
  CommonResource(name):
    assert std.objectHas(commonResources, name) : "common resources set '%s' doesn't exist" % name;
    commonResources[name],
  FromCompositeFieldPath(from, to):
    fromCompositeFieldPath(from, to),
  ToCompositeFieldPath(from, to):
    toCompositeFieldPath(from, to),
  PatchSetRef(name):
    patchSetRef(name),
  CompositeRef(xrd, version=''):
    compositeRef(xrd, version=version),
  conn: {
    FromSecretKey(name, from=name):
      connFromSecretKey(name, from=name),
    FromFieldPath(name, field):
      connFromFieldPath(name, field),
  },
}
