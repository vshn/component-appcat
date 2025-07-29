local kap = import 'lib/kapitan.libjsonnet';

local inv = kap.inventory();
local params = inv.parameters.appcat;
local vars = import 'config/vars.jsonnet';


local genGenericAlertingRule(serviceName, recordingRule=null) = {
  apiVersion: 'monitoring.coreos.com/v1',
  kind: 'PrometheusRule',
  metadata: {
    name: 'vshn-' + std.asciiLower(serviceName) + '-sla',
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
        name: 'appcat-' + std.asciiLower(serviceName) + '-sla-target',
        rules: [
          {
            alert: serviceName + 'Sla',
            // this query can be read as: if the rate of probes that are not successful is higher than 0.4 in the last 5 minutes and in the last minute, then alert
            // rate works on per second basis, so 0.4 means 40% of the probes are failing, which for 5 minutes is 2 minutes
            expr: 'rate(appcat_probes_seconds_count{reason!="success", service="' + serviceName + '", ha="false", maintenance="false"}[5m]) > 0.4',
            annotations: {
              summary: '{{$labels.service}} {{$labels.name}} down in {{$labels.namespace}}',
              title: '{{$labels.service}} {{$labels.name}} down in {{$labels.namespace}}',
            },
            labels: {
              OnCall: '{{ if eq $labels.sla "guaranteed" }}true{{ else }}false{{ end }}',
              runbook: 'https://kb.vshn.ch/app-catalog/how-tos/appcat/GuaranteedUptimeTarget.html',
              service: serviceName,
              severity: 'critical',
              syn: 'true',
              syn_team: 'schedar',
              syn_component: 'appcat',
            },
          },
          {
            alert: serviceName + 'SlaHA',
            // this query can be read as: if the rate of probes that are not successful is higher than 0.4 in the last 5 minutes and in the last minute, then alert
            // rate works on per second basis, so 0.4 means 40% of the probes are failing, which for 5 minutes is 2 minute
            expr: 'rate(appcat_probes_seconds_count{reason!="success", service="' + serviceName + '", ha="true"}[5m]) > 0.4',
            annotations: {
              summary: '{{$labels.service}} {{$labels.name}} down in {{$labels.namespace}}',
              title: '{{$labels.service}} {{$labels.name}} down in {{$labels.namespace}}',
            },
            labels: {
              OnCall: '{{ if eq $labels.sla "guaranteed" }}true{{ else }}false{{ end }}',
              runbook: 'https://kb.vshn.ch/app-catalog/how-tos/appcat/GuaranteedUptimeTarget.html',
              service: serviceName,
              severity: 'critical',
              syn: 'true',
              syn_team: 'schedar',
              syn_component: 'appcat',
            },
          },
        ] + (if recordingRule != null then [ recordingRule ] else []),
      },
    ],
  },
};


if params.slos.alertsEnabled && vars.isSingleOrServiceCluster then {
  GenGenericAlertingRule: genGenericAlertingRule,
} else {}
