local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local comp = import 'lib/appcat-compositions.libsonnet';
local crossplane = import 'lib/crossplane.libsonnet';

local common = import 'common.libsonnet';
local xrds = import 'xrds.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.appcat;
local rdsParams = params.services.aws.rds;

local connectionSecretKeys = [
  'address',
  'endpoint',
  'host',
  'port',
  'username',
  'password',
];

local xrd = xrds.XRDFromCRD(
  'xawsrds.aws.appcat.vshn.io',
  xrds.LoadCRD('aws.appcat.vshn.io_awsrds.yaml', params.images.appcat.tag),
  defaultComposition='awsrds.aws.appcat.vshn.io',
  connectionSecretKeys=connectionSecretKeys,
);

local logExports = {
  mysql: [
    'audit',
    'error',
    'general',
    'slowquery',
  ],
  mariadb: [
    'audit',
    'error',
    'general',
    'slowquery',
  ],
  postgresql: [
    'postgresql',
    'upgrade',
  ],
  mssql: [
    'agent',
    'error',
  ],
  oracle: [
    'alert',
    'audit',
    'listener',
    'trace',
  ],
};

local composition =
  local rdsBase =
    {
      apiVersion: 'rds.aws.upbound.io/v1beta1',
      kind: 'Instance',
      metadata: {},
      spec: {
        forProvider: {
          autoGeneratePassword: true,
          autoMinorVersionUpgrade: true,
          backupWindow: '',
          backupRetentionPeriod: 0,
          enabledCloudwatchLogsExports: [],
          maintenanceWindow: '',
          instanceClass: '',
          engine: '',
          engineVersion: '',
          Region: '',
          storageType: '',
          storageEncrypted: true,
          allocatedStorage: 0,
          username: '',
          publiclyAccessible: false,
          skipFinalSnapshot: true,
          passwordSecretRef: {
            name: '',
            key: 'password',
            namespace: rdsParams.providerSecretNamespace,
          }
        },
        providerConfigRef: {
          name: 'aws',
        },
        writeConnectionSecretToRef: {
          name: '',
          namespace: rdsParams.providerSecretNamespace,
        },
      },
    };
  local optionGroupBase =
    {
      apiVersion: 'rds.aws.upbound.io/v1beta1',
      kind: 'OptionGroup',
      metadata: {},
      spec: {
        forProvider: {
          engineName: '',
          majorEngineVersion: '',
          option: [
            {
              optionName: 'MARIADB_AUDIT_PLUGIN',
            }
          ],
          optionGroupDescription: 'Appcat Managed Option Group',
          region: '',
        },
        providerConfigRef: {
          name: 'aws',
        },
      },
      
    };
  local parameterGroupBase =
    {
      apiVersion: 'rds.aws.upbound.io/v1beta1',
      kind: 'ParameterGroup',
      metadata: {},
      spec: {
        forProvider: {
          description: 'Appcat Managed Parameter Group',
          family: '',
          parameter: [
            {
              applyMethod: 'immediate',
              name: 'general_log',
              value: '1',
            },
            {
              applyMethod: 'immediate',
              name: 'slow_query_log',
              value: '1',
            },
            {
              applyMethod: 'immediate',
              name: 'log_output',
              value: 'FILE',
            }
          ],
          region: '',
        },
        providerConfigRef: {
          name: 'aws',
        },
      },
    };
  local cloudWatchCPUBase =
    {
      apiVersion: 'cloudwatch.aws.upbound.io/v1beta1',
      kind: 'MetricAlarm',
      metadata: {},
      spec: {
        forProvider: {
          alarmDescription: 'Appcat Managed Metric: RDS CPU Utilization',
          comparisonOperator: 'GreaterThanOrEqualToThreshold',
          evaluationPeriods: 1,
          insufficientDataActions: [],
          metricName: 'CPUUtilization',
          namespace: 'AWS/RDS',
          period: 60,
          region: '',
          statistic: 'Average',
          threshold: 80, // 80%
          dimensions: {},
        },
        providerConfigRef: {
          name: 'aws',
        },
      },
    };
  local cloudWatchDiskBase =
    {
      apiVersion: 'cloudwatch.aws.upbound.io/v1beta1',
      kind: 'MetricAlarm',
      metadata: {},
      spec: {
        forProvider: {
          alarmDescription: 'Appcat Managed Metric: RDS Disk Utilization',
          comparisonOperator: 'LessThanOrEqualToThreshold',
          evaluationPeriods: 1,
          insufficientDataActions: [],
          metricName: 'FreeStorageSpace',
          namespace: 'AWS/RDS',
          period: 60,
          region: '',
          statistic: 'Average',
          threshold: 500000000, // 500MB
          dimensions: {},
        },
        providerConfigRef: {
          name: 'aws',
        },
      },
    };

  kube._Object('apiextensions.crossplane.io/v1', 'Composition', 'awsrds.aws.appcat.vshn.io') +
  common.SyncOptions +
  common.VshnMetaDBaaSAws('RDS')
  +
  {
    spec: {
      compositeTypeRef: comp.CompositeRef(xrd),
      writeConnectionSecretsToNamespace: rdsParams.secretNamespace,
      resources: [
        {
          base: rdsBase,
          connectionDetails: comp.conn.AllFromSecretKeys(connectionSecretKeys),
          patches: [
            comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'metadata.name'),
            comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'spec.writeConnectionSecretToRef.name'),
            
            comp.FromCompositeFieldPathWithTransformSuffix('metadata.labels[crossplane.io/composite]', 'spec.forProvider.passwordSecretRef.name', 'gen-password'),
            comp.FromCompositeFieldPath('spec.parameters.service.dbName', 'spec.forProvider.name'),
            comp.FromCompositeFieldPath('spec.parameters.service.engine', 'spec.forProvider.engine'),
            comp.FromCompositeFieldPath('spec.parameters.service.majorVersion', 'spec.forProvider.engineVersion'),
            comp.FromCompositeFieldPath('spec.parameters.service.region', 'spec.forProvider.region'),
            comp.FromCompositeFieldPath('spec.parameters.service.adminUser', 'spec.forProvider.username'),
            comp.FromCompositeFieldPath('spec.parameters.size.plan', 'spec.forProvider.instanceClass'),
            comp.FromCompositeFieldPath('spec.parameters.size.storageSize', 'spec.forProvider.allocatedStorage'),
            comp.FromCompositeFieldPath('spec.parameters.size.storageType', 'spec.forProvider.storageType'),
            comp.FromCompositeFieldPath('spec.parameters.maintenance.maintenanceWindow', 'spec.forProvider.maintenanceWindow'),
            comp.FromCompositeFieldPath('spec.parameters.backup.backupWindow', 'spec.forProvider.backupWindow'),
            comp.FromCompositeFieldPath('spec.parameters.backup.retentionPeriod', 'spec.forProvider.backupRetentionPeriod'),
            comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'spec.forProvider.optionGroupName'),
            comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'spec.forProvider.parameterGroupName'),
            comp.FromCompositeFieldPathWithTransformMap('spec.parameters.service.engine', 'spec.forProvider.enabledCloudwatchLogsExports', std.mapWithKey(function(key, x) x, logExports)),
          ],
        },
        {
          base: optionGroupBase,
          patches: [
            comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'metadata.name'),
            comp.FromCompositeFieldPath('spec.parameters.service.engine', 'spec.forProvider.engineName'),
            comp.FromCompositeFieldPath('spec.parameters.service.majorVersion', 'spec.forProvider.majorEngineVersion'),
            comp.FromCompositeFieldPath('spec.parameters.service.region', 'spec.forProvider.region'),
            comp.FromCompositeFieldPath('spec.parameters.service.rdsOptions', 'spec.forProvider.option'),
          ]
        },
        {
          base: parameterGroupBase,
          patches: [
            comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'metadata.name'),
            comp.CombineCompositeFromTwoFieldPaths('spec.parameters.service.engine', 'spec.parameters.service.majorVersion', 'spec.forProvider.family', '%s%s'),
            comp.FromCompositeFieldPath('spec.parameters.service.rdsOptions', 'spec.forProvider.parameter'),
            comp.FromCompositeFieldPath('spec.parameters.service.region', 'spec.forProvider.region'),
          ]
        },
        {
          base: cloudWatchCPUBase,
          patches: [
            comp.FromCompositeFieldPathWithTransformSuffix('metadata.labels[crossplane.io/composite]', 'metadata.name', 'cpu'),
            comp.FromCompositeFieldPath('spec.parameters.service.region', 'spec.forProvider.region'),
            comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'spec.forProvider.dimensions.DBInstanceIdentifier'),
          ]
        },
        {
          base: cloudWatchDiskBase,
          patches: [
            comp.FromCompositeFieldPathWithTransformSuffix('metadata.labels[crossplane.io/composite]', 'metadata.name', 'disk'),
            comp.FromCompositeFieldPath('spec.parameters.service.region', 'spec.forProvider.region'),
            comp.FromCompositeFieldPath('metadata.labels[crossplane.io/composite]', 'spec.forProvider.dimensions.DBInstanceIdentifier'),
          ]
        }
      ],
    },
  };

if params.services.aws.enabled && rdsParams.enabled then {
  '20_xrd_aws_rds': xrd,
  '20_rbac_aws_rds': xrds.CompositeClusterRoles(xrd),
  '21_composition_aws_rds': composition,
} else {}
