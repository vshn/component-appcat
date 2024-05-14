local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local comp = import 'lib/appcat-compositions.libsonnet';
local crossplane = import 'lib/crossplane.libsonnet';

local common = import 'common.libsonnet';
local prom = import 'prometheus.libsonnet';
local xrds = import 'xrds.libsonnet';

local slos = import 'slos.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.appcat;

local serviceNameLabelKey = 'appcat.vshn.io/servicename';
local serviceNamespaceLabelKey = 'appcat.vshn.io/claim-namespace';

local getServiceNamePlural(serviceName) =
  local serviceNameLower = std.asciiLower(serviceName);
  if std.endsWith(serviceName, 's') then
    serviceNameLower
  else
    serviceNameLower + 's';

local vshn_appcat_service(name, serviceParams) =
  local isOpenshift = std.startsWith(inv.parameters.facts.distribution, 'openshift') || inv.parameters.facts.distribution == 'oke';

  local connectionSecretKeys = serviceParams.connectionSecretKeys;
  local promRuleSLA = prom.PromRuleSLA(serviceParams.sla, serviceParams.serviceName);
  local plans = common.FilterDisabledParams(serviceParams.plans);
  local serviceNamePlural = getServiceNamePlural(serviceParams.serviceName);


  local restoreServiceAccount = kube.ServiceAccount(serviceParams.restoreSA) + {
    metadata+: {
      namespace: params.services.controlNamespace,
    },
  };

  local restoreRoleName = 'crossplane:appcat:job:' + name + ':restorejob';
  local restoreRole = kube.ClusterRole(restoreRoleName) {
    rules: serviceParams.restoreRoleRules,
  };

  local restoreClusterRoleBinding = kube.ClusterRoleBinding('appcat:job:' + name + ':restorejob') + {
    roleRef_: restoreRole,
    subjects_: [ restoreServiceAccount ],
  };

  local xrd = xrds.XRDFromCRD(
    'x' + serviceNamePlural + '.vshn.appcat.vshn.io',
    xrds.LoadCRD('vshn.appcat.vshn.io_' + serviceNamePlural + '.yaml', params.images.appcat.tag),
    defaultComposition=std.asciiLower(serviceParams.serviceName) + '.vshn.appcat.vshn.io',
    connectionSecretKeys=connectionSecretKeys,
  ) + xrds.WithPlanDefaults(plans, serviceParams.defaultPlan);

  local composition =
    kube._Object('apiextensions.crossplane.io/v1', 'Composition', std.asciiLower(serviceParams.serviceName) + '.vshn.appcat.vshn.io') +
    common.SyncOptions +
    common.vshnMetaVshnDBaas(name, serviceParams.mode, std.toString(serviceParams.offered), plans) +
    {
      spec: {
        compositeTypeRef: comp.CompositeRef(xrd),
        writeConnectionSecretsToNamespace: serviceParams.secretNamespace,
        mode: 'Pipeline',
        pipeline:
          [
            {
              step: name + '-func',
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
                        serviceName: name,
                        imageTag: common.GetAppCatImageTag(),
                        chartRepository: params.charts[name].source,
                        chartVersion: params.charts[name].version,
                        bucketRegion: serviceParams.bucket_region,
                        maintenanceSA: 'helm-based-service-maintenance',
                        controlNamespace: params.services.controlNamespace,
                        plans: std.toString(plans),
                        restoreSA: serviceParams.restoreSA,
                        quotasEnabled: std.toString(params.services.vshn.quotasEnabled),
                        isOpenshift: std.toString(isOpenshift),
                        sliNamespace: params.slos.namespace,
                        ownerKind: xrd.spec.names.kind,
                        ownerGroup: xrd.spec.group,
                        ownerVersion: xrd.spec.versions[0].name,
                      } + common.EmailAlerting(params.services.vshn.emailAlerting)
                      + std.get(serviceParams, 'additionalInputs', default={}, inc_hidden=true)
                      + if serviceParams.proxyFunction then {
                        proxyEndpoint: serviceParams.grpcEndpoint,
                      } else {},
              },
            },
          ],
      },
    };

  // OpenShift template configuration
  local templateObject = kube._Object('vshn.appcat.vshn.io/v1', serviceParams.serviceName, '${INSTANCE_NAME}') + {
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

  local osTemplate =
    common.OpenShiftTemplate(serviceParams.openshiftTemplate.serviceName,
                             serviceParams.serviceName,
                             serviceParams.openshiftTemplate.description,
                             serviceParams.openshiftTemplate.icon,
                             serviceParams.openshiftTemplate.tags,
                             serviceParams.openshiftTemplate.message,
                             'VSHN',
                             serviceParams.openshiftTemplate.url) + {
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
          value: name + '-credentials',
        },
        {
          name: 'INSTANCE_NAME',
        },
        {
          name: 'VERSION',
          value: std.toString(serviceParams.openshiftTemplate.defaultVersion),
        },
      ],
    };

  local plansCM = kube.ConfigMap('vshn' + name + 'plans') + {
    metadata+: {
      namespace: params.namespace,
    },
    data: {
      plans: std.toString(plans),
    },
  };

  if params.services.vshn.enabled && serviceParams.enabled then {
    ['20_xrd_vshn_%s' % name]: xrd,
    ['20_rbac_vshn_%s' % name]: xrds.CompositeClusterRoles(xrd),
    ['21_composition_vshn_%s' % name]: composition,
    ['20_role_vshn_%s_restore' % name]: [ restoreRole, restoreServiceAccount, restoreClusterRoleBinding ],
    ['20_plans_vshn_%s' % name]: plansCM,
    ['22_prom_rule_sla_%s' % name]: promRuleSLA,
    [if isOpenshift then '21_openshift_template_%s_vshn' % name]: osTemplate,
    [if params.services.vshn.enabled && serviceParams.enabled then 'sli_exporter/90_slo_vshn_%s' % name]: slos.Get('vshn-' + name),
    [if params.services.vshn.enabled && serviceParams.enabled then 'sli_exporter/90_slo_vshn_%s_ha' % name]: slos.Get('vshn-' + name + '-ha'),
  } else {}
;

std.foldl(function(objOut, newObj) objOut + vshn_appcat_service(newObj.name, newObj.value), common.FilterServiceByBoolean('compFunctionsOnly'), {})
