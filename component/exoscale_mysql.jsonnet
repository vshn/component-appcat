local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local comp = import 'lib/appcat-compositions.libsonnet';
local crossplane = import 'lib/crossplane.libsonnet';

local common = import 'common.libsonnet';
local xrds = import 'xrds.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.appcat;
local mysqlParams = params.exoscale.mysql;

local connectionSecretKeys = [
  'MYSQL_URL',
  'MYSQL_DB',
  'MYSQL_HOST',
  'MYSQL_PORT',
  'MYSQL_USER',
  'MYSQL_PASSWORD',
  'ca.crt',
];

local xrd = xrds.XRDFromCRD(
  'xexoscalemysqls.exoscale.appcat.vshn.io',
  xrds.LoadCRD('exoscale.appcat.vshn.io_exoscalemysqls.yaml'),
  defaultComposition='exoscalemysql.exoscale.appcat.vshn.io',
  connectionSecretKeys=connectionSecretKeys,
);


local composition =
  local mysqlBase =
    {
      apiVersion: 'exoscale.crossplane.io/v1',
      kind: 'MySQL',
      metadata: {},
      spec: {
        forProvider: {
          backup: {
            timeOfDay: '',
          },
          ipFilter: '',
          maintenance: {
            dayOfWeek: '',
            timeOfDay: '',
          },
          mysqlSettings: {},
          size: {
            plan: '',
          },
          terminationProtection: false,
          version: '',
          zone: '',
        },
        providerConfigRef: {
          name: 'exoscale',
        },
        writeConnectionSecretToRef: {
          name: '',
          namespace: mysqlParams.providerSecretNamespace,
        },
      },
    };

  kube._Object('apiextensions.crossplane.io/v1', 'Composition', 'exoscalemysql.exoscale.appcat.vshn.io') + common.SyncOptions +
  {
    spec: {
      compositeTypeRef: comp.CompositeRef(xrd),
      writeConnectionSecretsToNamespace: mysqlParams.secretNamespace,
      patchSets: [
        comp.PatchSet('annotations'),
        comp.PatchSet('labels'),
      ],
      resources: [
        {
          base: mysqlBase,
          connectionDetails: comp.conn.AllFromSecretKeys(connectionSecretKeys),
          patches: [
            comp.PatchSetRef('annotations'),
            comp.PatchSetRef('labels'),
            comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'metadata.name'),
            comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'spec.writeConnectionSecretToRef.name'),

            comp.FromCompositeFieldPath('spec.parameters.service.majorVersion', 'spec.forProvider.version'),
            comp.FromCompositeFieldPath('spec.parameters.service.mysqlSettings', 'spec.forProvider.mysqlSettings'),
            comp.FromCompositeFieldPath('spec.parameters.service.zone', 'spec.forProvider.zone'),
            comp.FromCompositeFieldPath('spec.parameters.network.ipFilter', 'spec.forProvider.ipFilter'),
            comp.FromCompositeFieldPath('spec.parameters.size.plan', 'spec.forProvider.size.plan'),
            comp.FromCompositeFieldPath('spec.parameters.maintenance.dayOfWeek', 'spec.forProvider.maintenance.dayOfWeek'),
            comp.FromCompositeFieldPath('spec.parameters.maintenance.timeOfDay', 'spec.forProvider.maintenance.timeOfDay'),
            comp.FromCompositeFieldPath('spec.parameters.backup.timeOfDay', 'spec.forProvider.backup.timeOfDay'),
          ],
        },
      ],
    },
  };


if params.exoscale.enabled && mysqlParams.enabled then {
  '20_xrd_exoscale_mysql': xrd,
  '20_rbac_exoscale_mysql': xrds.CompositeClusterRoles(xrd),
  '21_composition_exoscale_mysql': composition,
} else {}
