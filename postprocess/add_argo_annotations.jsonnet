local com = import 'lib/commodore.libjsonnet';
local inv = com.inventory();

local annotationMap = {
  Namespace: {
    'argocd.argoproj.io/sync-wave': '-100',
  },
  ServiceAccount: {
    'argocd.argoproj.io/sync-wave': '-100',
  },
  Role: {
    'argocd.argoproj.io/sync-wave': '-100',
  },
  ClusterRole: {
    'argocd.argoproj.io/sync-wave': '-100',
  },
  RoleBinding: {
    'argocd.argoproj.io/sync-wave': '-100',
  },
  Secrets: {
    'argocd.argoproj.io/sync-wave': '-100',
  },
  ClusterRoleBinding: {
    'argocd.argoproj.io/sync-wave': '-100',
  },
  Secret: {
    'argocd.argoproj.io/sync-wave': '-100',
  },
  ObjectBucket: {
    'argocd.argoproj.io/sync-options': 'Prune=false,SkipDryRunOnMissingResource=true',
  },
  DeploymentRuntimeConfig: {
    'argocd.argoproj.io/sync-wave': '-90',
    'argocd.argoproj.io/sync-options': 'SkipDryRunOnMissingResource=true',
  },
  Provider: {
    'argocd.argoproj.io/sync-wave': '-80',
    'argocd.argoproj.io/sync-options': 'SkipDryRunOnMissingResource=true',
  },
  CompositeResourceDefinition: {
    'argocd.argoproj.io/sync-wave': '-70',
    'argocd.argoproj.io/sync-options': 'SkipDryRunOnMissingResource=true',
  },
  Composition: {
    'argocd.argoproj.io/sync-wave': '-60',
    'argocd.argoproj.io/sync-options': 'SkipDryRunOnMissingResource=true',
  },
  ProviderConfig: {
    'argocd.argoproj.io/sync-wave': '-50',
    'argocd.argoproj.io/sync-options': 'SkipDryRunOnMissingResource=true',
  },
  Function: {
    'argocd.argoproj.io/sync-wave': '-40',
    'argocd.argoproj.io/sync-options': 'SkipDryRunOnMissingResource=true',
  },
};

local addArgoWave(obj) =
  local annotations = if std.objectHas(obj, 'kind') && std.objectHas(obj, 'metadata') then
    std.get(annotationMap, obj.kind, if std.objectHas(obj.metadata, 'annotations') then obj.metadata.annotations else null) else null;
  if std.type(obj) == 'object' then obj {
    metadata+: {
      [if std.type(annotations) != 'null' then 'annotations']+: annotations,
    },
  } else obj;

com.fixupDir(std.extVar('output_path'), addArgoWave)
