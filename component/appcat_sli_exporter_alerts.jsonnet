local vars = import 'config/vars.jsonnet';
local kap = import 'lib/kapitan.libjsonnet';

local inv = kap.inventory();
local params = inv.parameters.appcat;

if params.slos.enabled && params.slos.alertsEnabled && vars.isSingleOrServiceCluster then {
  'sli_exporter/90_AppCatSLIExporter_Opsgenie': {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'PrometheusRule',
    metadata: {
      name: 'appcat-sliexporter-health',
      namespace: params.slos.namespace,
      labels: {
        syn_team: 'schedar',
        syn_component: 'appcat',
        syn: 'true',
      },
    },
    spec: {
      groups: [
        {
          name: 'appcat-sliexporter-health',
          rules: [
            {
              alert: 'AppCatSLIExporterDown',
              expr: 'absent(up{job="appcat-sliexporter-controller-manager-metrics-service"}) or up{job="appcat-sliexporter-controller-manager-metrics-service"} == 0',
              'for': '5m',
              annotations: {
                description: 'The AppCat SLI exporter is not reachable by Prometheus. SLO measurements are not being collected, which may silently mask SLA violations.',
                summary: 'AppCat SLI exporter is down',
                title: 'AppCat SLI exporter is down',
              },
              labels: {
                OnCall: 'false',
                runbook: 'https://kb.vshn.ch/app-catalog/how-tos/appcat/AppCatSLIExporterDown.html',
                service: 'AppCatSLIExporter',
                severity: 'critical',
                syn: 'true',
                syn_team: 'schedar',
                syn_component: 'appcat',
              },
            },
          ],
        },
      ],
    },
  },
} else {}
