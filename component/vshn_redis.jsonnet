local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local comp = import 'lib/appcat-compositions.libsonnet';
local crossplane = import 'lib/appcat-crossplane.libsonnet';

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

local defaultUser = 'default';
local defaultPort = '6379';

local caCertificateSecretName = 'tls-ca-certificate';
local serverCertificateSecretName = 'tls-server-certificate';
local clientCertificateSecretName = 'tls-client-certificate';

local serviceNameLabelKey = 'appcat.vshn.io/servicename';
local serviceNamespaceLabelKey = 'appcat.vshn.io/claim-namespace';
local serviceCLaimNameLabelKey = 'appcat.vshn.io/claim-name';

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

local isOpenshift = std.startsWith(inv.parameters.facts.distribution, 'openshift') || inv.parameters.facts.distribution == 'oke';
local isBestEffort = !std.member([ 'guaranteed_availability', 'premium' ], inv.parameters.facts.service_level);

local securityContext = if isOpenshift then false else true;

local redisPlans = common.FilterDisabledParams(redisParams.plans);

local xrd = xrds.XRDFromCRD(
  'xvshnredis.vshn.appcat.vshn.io',
  xrds.LoadCRD('vshn.appcat.vshn.io_vshnredis.yaml', params.images.appcat.tag),
  defaultComposition='vshnredis.vshn.appcat.vshn.io',
  connectionSecretKeys=connectionSecretKeys,
) + xrds.WithPlanDefaults(redisPlans, redisParams.defaultPlan) + xrds.FilterOutGuaraanteed(isBestEffort);

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
  local selfSignedIssuer = comp.KubeObject('cert-manager.io/v1', 'Issuer') +
                           {
                             spec+: {
                               forProvider+: {
                                 manifest+: {
                                   metadata: {
                                     name: '',
                                     namespace: '',
                                   },
                                   spec: {
                                     selfSigned: {
                                       crlDistributionPoints: [],
                                     },
                                   },
                                 },
                               },
                             },
                           };
  local caCertificate = comp.KubeObject('cert-manager.io/v1', 'Certificate') +
                        {
                          spec+: {
                            forProvider+: {
                              manifest+: {
                                metadata: {
                                  name: '',
                                  namespace: '',
                                },
                                spec: {
                                  secretName: caCertificateSecretName,
                                  duration: '87600h',
                                  renewBefore: '2400h',
                                  subject: {
                                    organizations: [
                                      'vshn-appcat-ca',
                                    ],
                                  },
                                  isCA: true,
                                  privateKey: {
                                    algorithm: 'RSA',
                                    encoding: 'PKCS1',
                                    size: 4096,
                                  },
                                  dnsNames: [],
                                  issuerRef: {
                                    name: '',
                                    kind: 'Issuer',
                                    group: 'cert-manager.io',
                                  },
                                },
                              },
                            },
                          },
                        };
  local caIssuer = comp.KubeObject('cert-manager.io/v1', 'Issuer') +
                   {
                     spec+: {
                       forProvider+: {
                         manifest+: {
                           metadata: {
                             name: '',
                             namespace: '',
                           },
                           spec: {
                             ca: {
                               secretName: caCertificateSecretName,
                             },
                           },
                         },
                       },
                     },
                   };
  local serverCertificate = comp.KubeObject('cert-manager.io/v1', 'Certificate') +
                            {
                              spec+: {
                                forProvider+: {
                                  manifest+: {
                                    metadata: {
                                      name: '',
                                      namespace: '',
                                    },
                                    spec: {
                                      secretName: serverCertificateSecretName,
                                      duration: '87600h',
                                      renewBefore: '2400h',
                                      subject: {
                                        organizations: [
                                          'vshn-appcat-server',
                                        ],
                                      },
                                      isCA: false,
                                      privateKey: {
                                        algorithm: 'RSA',
                                        encoding: 'PKCS1',
                                        size: 4096,
                                      },
                                      usages: [
                                        'server auth',
                                        'client auth',
                                      ],
                                      dnsNames: [],
                                      issuerRef: {
                                        name: '',
                                        kind: 'Issuer',
                                        group: 'cert-manager.io',
                                      },
                                    },
                                  },
                                },
                              },
                            };
  local clientCertificate = comp.KubeObject('cert-manager.io/v1', 'Certificate') +
                            {
                              spec+: {
                                forProvider+: {
                                  manifest+: {
                                    metadata: {
                                      name: '',
                                      namespace: '',
                                    },
                                    spec: {
                                      secretName: clientCertificateSecretName,
                                      duration: '87600h',
                                      renewBefore: '2400h',
                                      subject: {
                                        organizations: [
                                          'vshn-appcat-client',
                                        ],
                                      },
                                      isCA: false,
                                      privateKey: {
                                        algorithm: 'RSA',
                                        encoding: 'PKCS1',
                                        size: 4096,
                                      },
                                      usages: [
                                        'client auth',
                                      ],
                                      dnsNames: [],
                                      issuerRef: {
                                        name: '',
                                        kind: 'Issuer',
                                        group: 'cert-manager.io',
                                      },
                                    },
                                  },
                                },
                              },
                            };

  local prometheusRule = prom.GeneratePrometheusNonSLORules('redis', 'redis', []) + {
    patches: [
      comp.FromCompositeFieldPathWithTransformSuffix('metadata.name', 'metadata.name', 'prometheusrule'),
      comp.FromCompositeFieldPathWithTransformPrefix('metadata.name', 'spec.forProvider.manifest.metadata.namespace', 'vshn-redis'),
    ],
  };


  local redisHelmChart =
    {
      apiVersion: 'helm.crossplane.io/v1beta1',
      kind: 'Release',
      spec+: {
        forProvider+: {
          chart: {
            name: 'redis',
            repository: params.charts.redis.source,
            version: redisParams.helmChartVersion,
          },
          values: {
            metrics: {
              enabled: true,
              // before all Your warning lamps start blinking,
              // this is internal communication on loopback interface
              // full mTLS isn't necessary
              extraEnvVars: [
                {
                  name: 'REDIS_EXPORTER_SKIP_TLS_VERIFICATION',
                  value: 'true',
                },
                {
                  name: 'REDIS_EXPORTER_INCL_SYSTEM_METRICS',
                  value: 'true',
                },
              ],
              containerSecurityContext: {
                enabled: securityContext,
              },
              serviceMonitor: {
                enabled: true,
                namespace: '',  // patched
              },
            },
            fullnameOverride: 'redis',
            global: {
              imageRegistry: redisParams.imageRegistry,
            },
            image: std.mergePatch(
              if redisParams.imageRegistry != '' then { registry: redisParams.imageRegistry } else {},
              { repository: 'bitnami/redis' }
            ),
            commonConfiguration: '',
            master: {
              persistence: {
                size: '',
              },
              podSecurityContext: {
                enabled: securityContext,
              },
              containerSecurityContext: {
                enabled: securityContext,
              },
              resources: {
                requests: {
                  cpu: '',
                  memory: '',
                },
                limits: {
                  cpu: '',
                  memory: '',
                },
              },
            },
            tls: {
              enabled: true,
              authClients: true,
              autoGenerated: false,
              existingSecret: serverCertificateSecretName,
              certFilename: 'tls.crt',
              certKeyFilename: 'tls.key',
              certCAFilename: 'ca.crt',
            },
            architecture: 'standalone',
          },
        },
        providerConfigRef: {
          name: 'helm',
        },
      },
    };

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
            step: 'patch-and-transform',
            functionRef: {
              name: 'function-patch-and-transform',
            },
            input: {
              apiVersion: 'pt.fn.crossplane.io/v1beta1',
              kind: 'Resources',
              resources: [
                {
                  name: 'self-signed-issuer',
                  base: selfSignedIssuer,
                  patches: [
                    comp.ToCompositeFieldPath('status.conditions', 'status.selfSignedIssuerConditions'),
                    comp.FromCompositeFieldPathWithTransformSuffix('metadata.name', 'metadata.name', 'selfsigned-issuer'),
                    comp.FromCompositeFieldPathWithTransformSuffix('metadata.name', 'spec.forProvider.manifest.metadata.name', 'selfsigned-issuer'),
                    comp.FromCompositeFieldPathWithTransformPrefix('metadata.name', 'spec.forProvider.manifest.metadata.namespace', 'vshn-redis'),
                  ],
                },
                {
                  name: 'local-ca',
                  base: caIssuer,
                  patches: [
                    comp.ToCompositeFieldPath('status.conditions', 'status.localCAConditions'),
                    comp.FromCompositeFieldPathWithTransformSuffix('metadata.name', 'metadata.name', 'ca-issuer'),
                    comp.FromCompositeFieldPathWithTransformSuffix('metadata.name', 'spec.forProvider.manifest.metadata.name', 'ca-issuer'),
                    comp.FromCompositeFieldPathWithTransformPrefix('metadata.name', 'spec.forProvider.manifest.metadata.namespace', 'vshn-redis'),
                  ],
                },
                {
                  name: 'certificate',
                  base: caCertificate,
                  patches: [
                    comp.ToCompositeFieldPath('status.conditions', 'status.caCertificateConditions'),
                    comp.FromCompositeFieldPathWithTransformSuffix('metadata.name', 'metadata.name', 'ca-certificate'),
                    comp.FromCompositeFieldPathWithTransformSuffix('metadata.name', 'spec.forProvider.manifest.metadata.name', 'ca'),
                    comp.FromCompositeFieldPathWithTransformSuffix('metadata.name', 'spec.forProvider.manifest.spec.issuerRef.name', 'selfsigned-issuer'),
                    comp.FromCompositeFieldPathWithTransformPrefix('metadata.name', 'spec.forProvider.manifest.metadata.namespace', 'vshn-redis'),
                    comp.CombineCompositeFromOneFieldPath('metadata.name', 'spec.forProvider.manifest.spec.dnsNames[0]', 'redis-headless.vshn-redis-%s.svc.cluster.local'),
                    comp.CombineCompositeFromOneFieldPath('metadata.name', 'spec.forProvider.manifest.spec.dnsNames[1]', 'redis-headless.vshn-redis-%s.svc'),

                  ],
                },
                {
                  name: 'server-certificate',
                  base: serverCertificate,
                  patches: [
                    comp.ToCompositeFieldPath('status.conditions', 'status.serverCertificateConditions'),
                    comp.FromCompositeFieldPathWithTransformSuffix('metadata.name', 'metadata.name', 'server-certificate'),
                    comp.FromCompositeFieldPathWithTransformSuffix('metadata.name', 'spec.forProvider.manifest.metadata.name', 'server'),
                    comp.FromCompositeFieldPathWithTransformSuffix('metadata.name', 'spec.forProvider.manifest.spec.issuerRef.name', 'ca-issuer'),
                    comp.FromCompositeFieldPathWithTransformPrefix('metadata.name', 'spec.forProvider.manifest.metadata.namespace', 'vshn-redis'),
                    comp.CombineCompositeFromOneFieldPath('metadata.name', 'spec.forProvider.manifest.spec.dnsNames[0]', 'redis-headless.vshn-redis-%s.svc.cluster.local'),
                    comp.CombineCompositeFromOneFieldPath('metadata.name', 'spec.forProvider.manifest.spec.dnsNames[1]', 'redis-headless.vshn-redis-%s.svc'),

                  ],
                },
                {
                  name: 'client-certificate',
                  base: clientCertificate,
                  patches: [
                    comp.ToCompositeFieldPath('status.conditions', 'status.clientCertificateConditions'),
                    comp.FromCompositeFieldPathWithTransformSuffix('metadata.name', 'metadata.name', 'client-certificate'),
                    comp.FromCompositeFieldPathWithTransformSuffix('metadata.name', 'spec.forProvider.manifest.metadata.name', 'client'),
                    comp.FromCompositeFieldPathWithTransformSuffix('metadata.name', 'spec.forProvider.manifest.spec.issuerRef.name', 'ca-issuer'),
                    comp.FromCompositeFieldPathWithTransformPrefix('metadata.name', 'spec.forProvider.manifest.metadata.namespace', 'vshn-redis'),
                    comp.CombineCompositeFromOneFieldPath('metadata.name', 'spec.forProvider.manifest.spec.dnsNames[0]', 'redis-headless.vshn-redis-%s.svc.cluster.local'),
                    comp.CombineCompositeFromOneFieldPath('metadata.name', 'spec.forProvider.manifest.spec.dnsNames[1]', 'redis-headless.vshn-redis-%s.svc'),
                  ],
                },
                {
                  name: 'release',
                  base: redisHelmChart,
                  patches: [
                    comp.FromCompositeFieldPath('metadata.name', 'metadata.name'),
                    comp.FromCompositeFieldPathWithTransformPrefix('metadata.name', 'spec.forProvider.namespace', 'vshn-redis'),
                    comp.FromCompositeFieldPathWithTransformPrefix('metadata.name', 'spec.forProvider.manifest.metadata.namespace', 'vshn-redis'),
                    comp.FromCompositeFieldPath('metadata.name', 'spec.forProvider.manifest.metadata.name'),

                    comp.FromCompositeFieldPathWithTransformMap('spec.parameters.size.plan', 'spec.forProvider.values.master.resources.requests.memory', std.mapWithKey(function(key, x) x.size.memory, redisPlans)),
                    comp.FromCompositeFieldPathWithTransformMap('spec.parameters.size.plan', 'spec.forProvider.values.master.resources.limits.memory', std.mapWithKey(function(key, x) x.size.memory, redisPlans)),
                    comp.FromCompositeFieldPath('spec.parameters.size.memoryRequests', 'spec.forProvider.values.master.resources.requests.memory'),
                    comp.FromCompositeFieldPath('spec.parameters.size.memoryLimits', 'spec.forProvider.values.master.resources.limits.memory'),

                    comp.FromCompositeFieldPathWithTransformMap('spec.parameters.size.plan', 'spec.forProvider.values.master.resources.requests.cpu', std.mapWithKey(function(key, x) x.size.cpu, redisPlans)),
                    comp.FromCompositeFieldPathWithTransformMap('spec.parameters.size.plan', 'spec.forProvider.values.master.resources.limits.cpu', std.mapWithKey(function(key, x) x.size.cpu, redisPlans)),
                    comp.FromCompositeFieldPath('spec.parameters.size.cpuRequests', 'spec.forProvider.values.master.resources.requests.cpu'),
                    comp.FromCompositeFieldPath('spec.parameters.size.cpuLimits', 'spec.forProvider.values.master.resources.limits.cpu'),

                    comp.FromCompositeFieldPathWithTransformMap('spec.parameters.size.plan', 'spec.forProvider.values.master.persistence.size', std.mapWithKey(function(key, x) x.size.disk, redisPlans)),
                    comp.FromCompositeFieldPath('spec.parameters.size.disk', 'spec.forProvider.values.master.persistence.size'),

                    comp.FromCompositeFieldPath('spec.parameters.tls.enabled', 'spec.forProvider.values.tls.enabled'),
                    comp.FromCompositeFieldPath('spec.parameters.tls.authClients', 'spec.forProvider.values.tls.authClients'),

                    comp.FromCompositeFieldPathWithTransformPrefix('metadata.name', 'spec.forProvider.values.metrics.serviceMonitor.namespace', 'vshn-redis'),

                    comp.FromCompositeFieldPathWithTransformMap('spec.parameters.size.plan',
                                                                'spec.forProvider.values.master.nodeSelector',
                                                                std.mapWithKey(function(key, x)
                                                                                 std.get(std.get(x, 'scheduling', default={}), 'nodeSelector', default={}),
                                                                               redisPlans)),
                    comp.FromCompositeFieldPath('spec.parameters.scheduling.nodeSelector', 'spec.forProvider.values.master.nodeSelector'),
                    comp.FromCompositeFieldPath('spec.parameters.service.redisSettings', 'spec.forProvider.values.commonConfiguration'),
                  ],
                },
              ],
            },
          },
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
                      serviceName: 'redis',
                      imageTag: common.GetAppCatImageTag(),
                      bucketRegion: redisParams.bucket_region,
                      maintenanceSA: 'helm-based-service-maintenance',
                      controlNamespace: params.services.controlNamespace,
                      restoreSA: 'redisrestoreserviceaccount',
                      quotasEnabled: std.toString(params.services.vshn.quotasEnabled),
                      ownerKind: xrd.spec.names.kind,
                      ownerGroup: xrd.spec.group,
                      ownerVersion: xrd.spec.versions[0].name,
                      isOpenshift: std.toString(isOpenshift),
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
   [if isOpenshift then '21_openshift_template_redis_vshn']: osTemplate,
 } else {})
+ if vars.isSingleOrServiceCluster then
  if params.services.vshn.enabled && params.services.vshn.redis.enabled then {
    'sli_exporter/70_slo_vshn_redis': slos.Get('vshn-redis'),
    'sli_exporter/80_slo_vshn_redis_ha': slos.Get('vshn-redis-ha'),
    [if params.slos.alertsEnabled then 'sli_exporter/90_VSHNRedis_Opsgenie']: opsgenieRules.GenGenericAlertingRule('VSHNRedis', promRuleRedisSLA),
  } else {}
else {}
