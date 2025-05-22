local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local comp = import 'lib/appcat-compositions.libsonnet';

local common = import 'common.libsonnet';
local vars = import 'config/vars.jsonnet';
local prom = import 'prometheus.libsonnet';
local slos = import 'slos.libsonnet';
local opsgenieRules = import 'vshn_alerting.jsonnet';
local xrds = import 'xrds.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.appcat;
local redisParams = params.services.vshn.redis;
local appuioManaged = inv.parameters.appcat.appuioManaged;

local serviceName = 'redis';

local connectionSecretKeys = [
  'ca.crt',
  'tls.crt',
  'tls.key',
  'REDIS_HOST',
  'REDIS_PORT',
  'REDIS_USERNAME',
  'REDIS_PASSWORD',
  'REDIS_URL',
];

local isBestEffort = !std.member([ 'guaranteed_availability', 'premium' ], inv.parameters.facts.service_level);

local securityContext = if vars.isServiceClusterOpenShift then false else true;

local redisPlans = common.FilterDisabledParams(redisParams.plans);

local xrd = xrds.XRDFromCRD(
              'xvshnredis.vshn.appcat.vshn.io',
              xrds.LoadCRD('vshn.appcat.vshn.io_vshnredis.yaml', params.images.appcat.tag),
              defaultComposition='vshnredis.vshn.appcat.vshn.io',
              connectionSecretKeys=connectionSecretKeys,
            )
            + xrds.WithPlanDefaults(redisPlans, redisParams.defaultPlan)
            + xrds.FilterOutGuaraanteed(isBestEffort)
            + xrds.WithServiceID(serviceName);

local promRuleRedisSLA = prom.PromRecordingRuleSLA(params.services.vshn.redis.sla, 'VSHNRedis');

local restoreServiceAccount = kube.ServiceAccount('redisrestoreserviceaccount') + {
  metadata+: {
    namespace: params.services.controlNamespace,
  },
};

local restoreRoleName = 'crossplane:appcat:job:redis:restorejob';
local restoreRole = kube.ClusterRole(restoreRoleName) {
  rules: [
    {
      apiGroups: [ 'vshn.appcat.vshn.io' ],
      resources: [ 'vshnredis' ],
      verbs: [ 'get' ],
    },
    {
      apiGroups: [ 'k8up.io' ],
      resources: [ 'snapshots' ],
      verbs: [ 'get' ],
    },
    {
      apiGroups: [ '' ],
      resources: [ 'secrets' ],
      verbs: [ 'get', 'create', 'delete' ],
    },
    {
      apiGroups: [ 'apps' ],
      resources: [ 'statefulsets/scale' ],
      verbs: [ 'update', 'patch' ],
    },
    {
      apiGroups: [ 'apps' ],
      resources: [ 'statefulsets' ],
      verbs: [ 'get' ],
    },
    {
      apiGroups: [ 'batch' ],
      resources: [ 'jobs' ],
      verbs: [ 'get' ],
    },
    {
      apiGroups: [ '' ],
      resources: [ 'events' ],
      verbs: [ 'get', 'create', 'patch' ],
    },
  ],
};

local restoreClusterRoleBinding = kube.ClusterRoleBinding('appcat:job:redis:restorejob') + {
  roleRef_: restoreRole,
  subjects_: [ restoreServiceAccount ],
};

local composition =
  kube._Object('apiextensions.crossplane.io/v1', 'Composition', 'vshnredis.vshn.appcat.vshn.io') +
  common.SyncOptions +
  common.vshnMetaVshnDBaas('Redis', 'standalone', 'true', redisPlans) +
  {
    spec: {
      compositeTypeRef: comp.CompositeRef(xrd),
      writeConnectionSecretsToNamespace: redisParams.secretNamespace,
      mode: 'Pipeline',
      pipeline:
        [
          {
            step: 'redis-func',
            functionRef: {
              name: 'function-appcat',
            },
            input: kube.ConfigMap('xfn-config') + {
              metadata: {
                labels: {
                  name: 'xfn-config',
                },
                name: 'xfn-config',
              },
              data: {
                      serviceName: serviceName,
                      serviceID: common.VSHNServiceID(serviceName),
                      imageTag: common.GetAppCatImageTag(),
                      chartRepository: params.charts[serviceName].source,
                      chartVersion: params.charts[serviceName].version,
                      bucketRegion: common.GetBucketRegion(),
                      maintenanceSA: 'helm-based-service-maintenance',
                      controlNamespace: params.services.controlNamespace,
                      restoreSA: 'redisrestoreserviceaccount',
                      quotasEnabled: std.toString(params.services.vshn.quotasEnabled),
                      plans: std.toString(redisPlans),
                      ownerKind: xrd.spec.names.kind,
                      ownerGroup: xrd.spec.group,
                      ownerVersion: xrd.spec.versions[0].name,
                      isOpenshift: std.toString(vars.isServiceClusterOpenShift),
                      sliNamespace: params.slos.namespace,
                      salesOrder: if appuioManaged then std.toString(params.billing.salesOrder) else '',
                      crossplaneNamespace: params.crossplane.namespace,
                      ignoreNamespaceForBilling: params.billing.ignoreNamespace,
                      imageRegistry: redisParams.imageRegistry,
                    } + common.EmailAlerting(params.services.emailAlerting)
                    + if redisParams.proxyFunction then {
                      proxyEndpoint: redisParams.grpcEndpoint,
                    } else {},
            },
          },
        ],
    },
  };

// OpenShift template configuration
local templateObject = kube._Object('vshn.appcat.vshn.io/v1', 'VSHNRedis', '${INSTANCE_NAME}') + {
  spec: {
    parameters: {
      service: {
        version: '${VERSION}',
      },
      size: {
        plan: '${PLAN}',
      },
    },
    writeConnectionSecretToRef: {
      name: '${SECRET_NAME}',
    },
  },
};

local templateDescription = 'The open source, in-memory data store used by millions of developers as a database, cache, streaming engine, and message broker.';
local templateMessage = 'Your Redis by VSHN instance is being provisioned, please see ${SECRET_NAME} for access.';

local osTemplate =
  common.OpenShiftTemplate('redisbyvshn',
                           'Redis',
                           templateDescription,
                           'icon-redis',
                           'database,nosql',
                           templateMessage,
                           'VSHN',
                           'https://vs.hn/vshn-redis') + {
    objects: [
      templateObject,
    ],
    parameters: [
      {
        name: 'PLAN',
        value: 'standard-4',
      },
      {
        name: 'SECRET_NAME',
        value: 'redis-credentials',
      },
      {
        name: 'INSTANCE_NAME',
      },
      {
        name: 'VERSION',
        value: '7.0',
      },
    ],
  };

local plansCM = kube.ConfigMap('vshnredisplans') + {
  metadata+: {
    namespace: params.namespace,
  },
  data: {
    plans: std.toString(redisPlans),
  },
};

(if params.services.vshn.enabled && redisParams.enabled && vars.isSingleOrControlPlaneCluster then {
   '20_xrd_vshn_redis': xrd,
   '20_rbac_vshn_redis': xrds.CompositeClusterRoles(xrd),
   '20_role_vshn_redisrestore': [ restoreRole, restoreServiceAccount, restoreClusterRoleBinding ],
   '20_plans_vshn_redis': plansCM,
   '21_composition_vshn_redis': composition,
   [if vars.isOpenshift then '21_openshift_template_redis_vshn']: osTemplate,
 } else {})
+ if vars.isSingleOrServiceCluster then
  if params.services.vshn.enabled && params.services.vshn.redis.enabled then {
    'sli_exporter/70_slo_vshn_redis': slos.Get('vshn-redis'),
    'sli_exporter/80_slo_vshn_redis_ha': slos.Get('vshn-redis-ha'),
    [if params.slos.alertsEnabled then 'sli_exporter/90_VSHNRedis_Opsgenie']: opsgenieRules.GenGenericAlertingRule('VSHNRedis', promRuleRedisSLA),
  } else {}
else {}
