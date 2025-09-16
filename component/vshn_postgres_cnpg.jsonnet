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
local pgParams = params.services.vshn.postgres;
local appuioManaged = inv.parameters.appcat.appuioManaged;
local serviceName = 'postgresqlcnpg';

local connectionSecretKeys = [
  'ca.crt',
  'tls.crt',
  'tls.key',
  'POSTGRESQL_URL',
  'POSTGRESQL_DB',
  'POSTGRESQL_HOST',
  'POSTGRESQL_PORT',
  'POSTGRESQL_USER',
  'POSTGRESQL_PASSWORD',
  'LOADBALANCER_IP',
];

local isBestEffort = !std.member([ 'guaranteed_availability', 'premium' ], inv.parameters.facts.service_level);
local pgPlans = common.FilterDisabledParams(pgParams.plans);
local xrd = xrds.XRDFromCRD(
              'xvshnpostgresqls.vshn.appcat.vshn.io',
              xrds.LoadCRD('vshn.appcat.vshn.io_vshnpostgresqls.yaml', params.images.appcat.tag),
              defaultComposition='vshnpostgres.vshn.appcat.vshn.io',
              connectionSecretKeys=connectionSecretKeys,
            )
            + xrds.WithPlanDefaults(pgPlans, pgParams.defaultPlan)
            + xrds.FilterOutGuaraanteed(isBestEffort)
            + xrds.WithServiceID(serviceName);

local additionalMaintenanceClusterRoleName = 'crossplane:appcat:job:postgres:maintenance';

local composition =
  kube._Object('apiextensions.crossplane.io/v1', 'Composition', 'vshnpostgrescnpg.vshn.appcat.vshn.io') +
  common.SyncOptions +
  common.vshnMetaVshnDBaas('PostgreSQL', 'standalone', 'true', pgPlans) +
  {
    spec: {
      compositeTypeRef: {
        apiVersion: "vshn.appcat.vshn.io/v1",
        kind: "XVSHNPostgreSQL",
      },/*comp.CompositeRef(xrd),*/
      writeConnectionSecretsToNamespace: pgParams.secretNamespace,
      mode: 'Pipeline',
      pipeline:
        [
          {
            step: 'pgsql-func',
            functionRef: {
              name: common.GetCurrentFunctionName(),
            },
            input: kube.ConfigMap('xfn-config') + {
              metadata: {
                labels: {
                  name: 'xfn-config',
                },
                name: 'xfn-config',
              },
              data: {
                      externalDatabaseConnectionsEnabled: std.toString(params.services.vshn.externalDatabaseConnectionsEnabled),
                      additionalMaintenanceClusterRole: additionalMaintenanceClusterRoleName,
                    } + common.GetDefaultInputs(serviceName, pgParams, pgPlans, xrd, appuioManaged)
                    + std.get(pgParams, 'additionalInputs', default={}, inc_hidden=true)
                    + common.EmailAlerting(params.services.emailAlerting)
                    + if pgParams.proxyFunction then {
                      proxyEndpoint: pgParams.grpcEndpoint,
                    } else {},
            },
          },
        ],
    },
  };

if params.services.vshn.enabled && pgParams.enabled && vars.isSingleOrControlPlaneCluster then {
  '21_composition_vshn_postgrescnpg': composition,
} else {}
