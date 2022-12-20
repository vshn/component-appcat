local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local comp = import 'lib/appcat-compositions.libsonnet';
local crossplane = import 'lib/crossplane.libsonnet';

local common = import 'common.libsonnet';
local xrds = import 'xrds.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.appcat;
local kafkaParams = params.exoscale.kafka;

local connectionSecretKeys = [
  'KAFKA_URI',
  'KAFKA_HOST',
  'KAFKA_PORT',
  'KAFKA_NODES',
  'service.cert',
  'service.key',
  'ca.crt',
];

local xrd = xrds.XRDFromCRD(
  'xexoscalekafkas.exoscale.appcat.vshn.io',
  xrds.LoadCRD('exoscale.appcat.vshn.io_exoscalekafkas.yaml'),
  connectionSecretKeys=connectionSecretKeys,
);


local composition =
  local kafkaBase =
    {
      apiVersion: 'exoscale.crossplane.io/v1',
      kind: 'Kafka',
      metadata: {},
      spec: {
        forProvider: {
          ipFilter: '',
          kafkaSettings: {},
          maintenance: {
            dayOfWeek: '',
            timeOfDay: '',
          },
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
          namespace: kafkaParams.providerSecretNamespace,
        },
      },
    };

  kube._Object('apiextensions.crossplane.io/v1', 'Composition', 'exoscalekafka.exoscale.appcat.vshn.io') + common.SyncOptions +
  {
    spec: {
      compositeTypeRef: comp.CompositeRef(xrd),
      writeConnectionSecretsToNamespace: kafkaParams.secretNamespace,
      patchSets: [
        comp.PatchSet('annotations'),
        comp.PatchSet('labels'),
      ],
      resources: [
        {
          base: kafkaBase,
          connectionDetails: comp.conn.AllFromSecretKeys(connectionSecretKeys),
          patches: [
            comp.PatchSetRef('annotations'),
            comp.PatchSetRef('labels'),
            comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'metadata.name'),
            comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'spec.writeConnectionSecretToRef.name'),

            comp.FromCompositeFieldPath('spec.parameters.service.kafkaSettings', 'spec.forProvider.kafkaSettings'),
            comp.FromCompositeFieldPath('spec.parameters.service.zone', 'spec.forProvider.zone'),
            comp.FromCompositeFieldPath('spec.parameters.network.ipFilter', 'spec.forProvider.ipFilter'),
            comp.FromCompositeFieldPath('spec.parameters.size.plan', 'spec.forProvider.size.plan'),
            comp.FromCompositeFieldPath('spec.parameters.maintenance.dayOfWeek', 'spec.forProvider.maintenance.dayOfWeek'),
            comp.FromCompositeFieldPath('spec.parameters.maintenance.timeOfDay', 'spec.forProvider.maintenance.timeOfDay'),
            comp.FromCompositeFieldPath('spec.parameters.service.version', 'spec.forProvider.version'),
            comp.ToCompositeFieldPath('status.atProvider.version', 'status.version'),
          ],
        },
      ],
    },
  };


if params.exoscale.enabled && kafkaParams.enabled then {
  '20_xrd_exoscale_kafka': xrd,
  '20_rbac_exoscale_kafka': xrds.CompositeClusterRoles(xrd),
  '21_composition_exoscale_kafka': composition,
} else {}
