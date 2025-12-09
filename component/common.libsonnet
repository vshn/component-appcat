local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local comp = import 'lib/appcat-compositions.libsonnet';

local rbac = import 'rbac.libsonnet';

local inv = kap.inventory();
local facts = inv.parameters.facts;
local params = inv.parameters.appcat;

local exoscaleZones = params.cloudRegionMap.exoscale;
local cloudscaleZones = params.cloudRegionMap.cloudscale;

local strExoscaleZones = std.join(', ', exoscaleZones);
local strCloudscaleZones = std.join(', ', cloudscaleZones);

local vars = import 'config/vars.jsonnet';

local vshnServiceID(name) = 'vshn-' + std.asciiLower(name);
local objectBucketServiceID(name) = std.asciiLower(std.rstripChars(name, '.ch')) + '-objectbucket';

local syncOptions = {
  metadata+: {
    annotations+: {
      'argocd.argoproj.io/sync-options': 'SkipDryRunOnMissingResource=true',
    },
  },
};

local vshnMetaDBaaSExoscale(dbname) = {
  metadata+: {
    annotations+: {
      'metadata.appcat.vshn.io/displayname': 'Exoscale ' + dbname,
      'metadata.appcat.vshn.io/description': dbname + ' DBaaS instances by Exoscale',
      'metadata.appcat.vshn.io/end-user-docs-url': 'https://vs.hn/exo-' + std.asciiLower(dbname),
      'metadata.appcat.vshn.io/zone': strExoscaleZones,
      'metadata.appcat.vshn.io/product-description': 'https://products.docs.vshn.ch/products/appcat/exoscale_dbaas.html',
    },
    labels+: {
      'metadata.appcat.vshn.io/offered': 'true',
      'metadata.appcat.vshn.io/serviceID': 'exoscale-' + std.asciiLower(dbname),
    },
  },
};

local getAppCatImageTag() = std.strReplace(params.images.appcat.tag, '/', '_');
local getAppCatVersion() = std.strReplace(inv.parameters.components.appcat.version, '/', '_');

local truncateName(rev) =
  if std.length(rev) > 63 then
    std.substr(rev, 0, 56) + '-' + std.substr(std.md5(rev), 0, 5)
  else
    rev;

local vshnMetaVshn(servicename, flavor, offered, plans) = {
  metadata+: {
    annotations+: {
      'metadata.appcat.vshn.io/displayname': servicename + ' by VSHN',
      'metadata.appcat.vshn.io/description': servicename + ' instances by VSHN',
      'metadata.appcat.vshn.io/end-user-docs-url': 'https://vs.hn/vshn-' + std.asciiLower(servicename),
      'metadata.appcat.vshn.io/flavor': flavor,
      'metadata.appcat.vshn.io/plans': std.manifestJsonMinified(plans),
      'metadata.appcat.vshn.io/product-description': 'https://products.docs.vshn.ch/products/appcat/' + std.asciiLower(servicename) + '.html',
    },
    labels+: {
      'metadata.appcat.vshn.io/offered': offered,
      'metadata.appcat.vshn.io/serviceID': vshnServiceID(servicename),
      'metadata.appcat.vshn.io/revision': truncateName(getAppCatVersion() + '-' + getAppCatImageTag()),
    },
  },
};

local vshnMetaVshnDBaas(dbname, flavor, offered, plans) = vshnMetaVshn(dbname, flavor, offered, plans) + {
  metadata+: {
    annotations+: {
      'metadata.appcat.vshn.io/zone': facts.region,
    },
  },
};

local providerZones(provider) =
  if provider == 'Exoscale' then strExoscaleZones
  else if provider == 'cloudscale.ch' then strCloudscaleZones
  else 'default';

local vshnMetaObjectStorage(provider) = {
  metadata+: {
    annotations+: {
      'metadata.appcat.vshn.io/displayname': provider + ' Object Storage',
      'metadata.appcat.vshn.io/description': 'S3 compatible object storage hosted by ' + provider,
      'metadata.appcat.vshn.io/end-user-docs-url': 'https://vs.hn/objstor',
      'metadata.appcat.vshn.io/zone': providerZones(provider),
      'metadata.appcat.vshn.io/product-description': 'https://products.docs.vshn.ch/products/appcat/objectstorage.html',
    },
    labels+: {
      'metadata.appcat.vshn.io/offered': 'true',
      'metadata.appcat.vshn.io/serviceID': objectBucketServiceID(provider),
    },
  },
};

local mergeArgs(args, additional) =
  local foldFn =
    function(acc, arg)
      local ap = std.splitLimit(arg, '=', 1);
      acc { [ap[0]]: ap[1] };
  local base = std.foldl(foldFn, args, {});
  local final = std.foldl(foldFn, additional, base);
  [ '%s=%s' % [ k, final[k] ] for k in std.objectFields(final) ];


local filterDisabledParams(params) = std.foldl(
  function(ps, key)
    local p = params[key];
    local enabled = p != null && p != {} && std.get(p, 'enabled', true);
    ps {
      [if enabled then key]: p,
    },
  std.objectFields(params),
  {}
);

local openShiftTemplate(name, displayName, description, iconClass, tags, message, provider, docs)
      = kube._Object('template.openshift.io/v1', 'Template', name) + {
  metadata+: {
    annotations: {
      'openshift.io/display-name': displayName,
      description: description,
      iconClass: iconClass,
      tags: tags,
      'openshift.io/provider-display-name': provider,
      'openshift.io/documentation-url': docs,
      'openshift.io/support-url': 'https://www.vshn.ch/en/contact/',
    },
    namespace: 'openshift',
  },
  message: message,
};

local emailAlerting(alertingSettings) = {
  emailAlertingEnabled: std.toString(alertingSettings.enabled),
  emailAlertingSecretNamespace: alertingSettings.secretNamespace,
  emailAlertingSecretName: alertingSettings.secretName,
  emailAlertingSmtpFromAddress: alertingSettings.smtpFromAddress,
  emailAlertingSmtpUsername: alertingSettings.smtpUsername,
  emailAlertingSmtpHost: alertingSettings.smtpHost,
};

local getApiserverImageTag() = std.strReplace(params.images.apiserver.tag, '/', '_');

local getAppCatImageString() = params.images.appcat.registry + '/' + params.images.appcat.repository + ':' + getAppCatImageTag();

local getApiserverImageString() = params.images.apiserver.registry + '/' + params.images.apiserver.repository + ':' + getApiserverImageTag();

local removeField(obj, name) = {
  // We don't want the name field in the actual providerConfig
  [k]: obj[k]
  for k in std.objectFieldsAll(obj)
  if k != name
};

local argoCDAnnotations() = {
  // Our current ArgoCD configuration can't handle the claim -> composite
  // relationship
  'argocd.argoproj.io/compare-options': 'IgnoreExtraneous',
  'argocd.argoproj.io/sync-options': 'Prune=false',
};

local defaultReadinessCheck() = {
  readinessChecks: [
    {
      matchCondition: {
        status: 'True',
        type: 'Ready',
      },
      type: 'MatchCondition',
    },
    {
      matchCondition: {
        status: 'True',
        type: 'Ready',
      },
      type: 'MatchCondition',
    },
  ],
};

local defaultRuntimeConfigWithSaName(name) = {
  apiVersion: 'pkg.crossplane.io/v1beta1',
  kind: 'DeploymentRuntimeConfig',
  metadata: {
    name: name,
  },
  spec: {
    deploymentTemplate: {
      spec: {
        selector: {},
        template: {
          spec:
            {
              containers: [
                {
                  name: 'package-runtime',
                  securityContext: {},
                },
              ],
              securityContext: {},
              serviceAccountName: name,
            },
        },
      },
    },
  },
};

local capitalize = function(str)
  std.join('', std.mapWithIndex(function(i, c) if i == 0 then std.asciiUpper(c) else c, std.stringChars(str)));

local keysAndValues(obj) = std.map(function(x) { name: x, value: obj[x] }, std.objectFields(obj));

local filterServiceByBoolean(fieldName) = std.filter(function(r) std.type(r.value) == 'object' && std.objectHas(r.value, fieldName) && r.value[fieldName], keysAndValues(params.services.vshn));


local keysAndStringValues(obj, field) = if std.objectHas(obj, field) then {
  [k]: std.toString(obj[field][k])
  for k in std.objectFieldsAll(obj[field])
} else {};

local removeFields(obj, names) = [
  removeField(obj, name)
  for name in names
];

local controlPlaneSa = kube.ServiceAccount('appcat-control-plane') + {
  metadata+: {
    namespace: params.namespace,
  },
};

local getBucketRegion() =
  if params.bucketRegionOverride != '' then
    params.bucketRegionOverride
  else
    local regions = std.get(params.cloudRegionMap, facts.cloud);

    local nonLocalRegions = std.filter(function(x) x != facts.region, regions);

    nonLocalRegions[0];

local getCurrentFunctionName() =
  truncateName(
    std.strReplace('function-appcat-' + std.strReplace(getAppCatVersion(), '_', '-') + '-' + std.strReplace(getAppCatImageTag(), '_', '-'), '.', '-')
  );

local getDefaultInputs(name, serviceParams, plans, xrd, appuioManaged) = {
  serviceName: name,
  serviceID: vshnServiceID(name),
  [if std.objectHas(serviceParams, 'mode') then 'mode']: serviceParams.mode,
  imageTag: getAppCatImageTag(),
  bucketRegion: getBucketRegion(),
  maintenanceSA: 'helm-based-service-maintenance',
  controlNamespace: params.services.controlNamespace,
  plans: std.toString(plans),
  defaultPlan: serviceParams.defaultPlan,
  quotasEnabled: std.toString(params.services.vshn.quotasEnabled),
  cloudProvider: inv.parameters.facts.cloud,
  isOpenshift: std.toString(vars.isServiceClusterOpenShift),
  sliNamespace: params.slos.namespace,
  ocpDefaultAppsDomain: params.services.vshn.ocpDefaultAppsDomain,
  ownerKind: xrd.spec.names.kind,
  ownerGroup: xrd.spec.group,
  ownerVersion: xrd.spec.versions[0].name,
  salesOrder: if appuioManaged then std.toString(params.billing.salesOrder) else '',
  [if std.objectHas(serviceParams, 'sideCars') then 'sideCars']: std.toString(serviceParams.sideCars),
  crossplaneNamespace: params.crossplane.namespace,
  ignoreNamespaceForBilling: params.billing.ignoreNamespace,
  billingUnitID: params.billing.instanceUOM,
  crDeletionAfter: params.billing.customResourceDeletionAfter,
  billingEnabled: std.toString(params.billingEnabled),
  clusterName: inv.parameters.cluster.name,
  [if std.objectHas(serviceParams, 'imageRegistry') then 'imageRegistry']: serviceParams.imageRegistry,
  [if std.objectHas(serviceParams, 'imageRepositoryPrefix') then 'imageRepositoryPrefix']: serviceParams.imageRepositoryPrefix,
  [if std.objectHas(serviceParams, 'maintenanceURL') then 'maintenanceURL']: serviceParams.maintenanceURL,
  releaseManagementEnabled: std.toString(params.deploymentManagementSystem.enabled),
  minimumRevisionAge: params.deploymentManagementSystem.minimumRevisionAge,
} + (if std.objectHas(params.charts, name) then {
       chartRepository: params.charts[name].source,
       chartVersion: params.charts[name].version,
     } else {}) + emailAlerting(params.services.emailAlerting);

{
  SyncOptions: syncOptions,
  VshnMetaDBaaSExoscale(dbname):
    vshnMetaDBaaSExoscale(dbname),
  VshnMetaObjectStorage(provider):
    vshnMetaObjectStorage(provider),
  MergeArgs(args, additional):
    mergeArgs(args, additional),
  VshnMetaVshn(servicename, flavor, offered='true', plans):
    vshnMetaVshn(servicename, flavor, offered, plans),
  vshnMetaVshnDBaas(dbname, flavor, offered='true', plans):
    vshnMetaVshnDBaas(dbname, flavor, offered, plans),
  FilterDisabledParams(params):
    filterDisabledParams(params),
  OpenShiftTemplate(name, displayName, description, iconClass, tags, message, provider, docs):
    openShiftTemplate(name, displayName, description, iconClass, tags, message, provider, docs),
  GetAppCatImageString():
    getAppCatImageString(),
  GetAppCatVersion():
    getAppCatVersion(),
  GetAppCatImageTag():
    getAppCatImageTag(),
  GetApiserverImageTag():
    getApiserverImageTag(),
  GetApiserverImageString():
    getApiserverImageString(),
  RemoveField(obj, name):
    removeField(obj, name),
  ArgoCDAnnotations():
    argoCDAnnotations(),
  EmailAlerting(alertingSettings):
    emailAlerting(alertingSettings),
  DefaultReadinessCheck():
    defaultReadinessCheck(),
  DefaultRuntimeConfigWithSaName(name):
    defaultRuntimeConfigWithSaName(name),
  Capitalize(str):
    capitalize(str),
  KeysAndValues(obj):
    keysAndValues(obj),
  FilterServiceByBoolean(fieldName):
    filterServiceByBoolean(fieldName),
  KeysAndStringValues(object, fieldName):
    keysAndStringValues(object, fieldName),
  RemoveFields(obj, names):
    removeFields(obj, names),
  ControlPlaneSa: controlPlaneSa,
  VSHNServiceID(name):
    vshnServiceID(name),
  ObjectBucketServiceID(name):
    objectBucketServiceID(name),
  GetBucketRegion():
    getBucketRegion(),
  GetCurrentFunctionName():
    getCurrentFunctionName(),
  GetDefaultInputs(name, serviceParams, plans, xrd, appuioManaged):
    getDefaultInputs(name, serviceParams, plans, xrd, appuioManaged),
}
