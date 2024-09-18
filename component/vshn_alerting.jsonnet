local kap = import 'lib/kapitan.libjsonnet';

local inv = kap.inventory();
local params = inv.parameters.appcat;


local genGenericAlertingRule(serviceName) = {
  apiVersion: 'monitoring.coreos.com/v1',
  kind: 'PrometheusRule',
  metadata: {
    name: 'vshn-' + std.asciiLower(serviceName) + '-guaranteed-uptime',
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
        name: 'appcat-' + std.asciiLower(serviceName) + '-guaranteed-uptime-target',
        rules: [
          {
            alert: 'vshn-' + std.asciiLower(serviceName) + '-guaranteed-uptime',
            // this query can be read as: if the rate of probes that are not successful is higher than 0.2 in the last 5 minutes and in the last minute, then alert
            // rate works on per second basis, so 0.2 means 20% of the probes are failing, which for 5 minutes is 1 minute and for 1 minute is 45 seconds
            expr: 'rate(appcat_probes_seconds_count{reason!="success", service="' + serviceName + '", ha="false", maintenance="false"}[5m]) > 0.2 and rate(appcat_probes_seconds_count{reason!="success", service="' + serviceName + '", ha="false", maintenance="false"}[1m]) > 0.75',
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
            alert: 'vshn-' + std.asciiLower(serviceName) + '-sla-ha',
            // this query can be read as: if the rate of probes that are not successful is higher than 0.2 in the last 5 minutes and in the last minute, then alert
            // rate works on per second basis, so 0.2 means 20% of the probes are failing, which for 5 minutes is 1 minute and for 1 minute is 45 seconds
            expr: 'rate(appcat_probes_seconds_count{reason!="success", service="' + serviceName + '", ha="true"}[5m]) > 0.2 and rate(appcat_probes_seconds_count{reason!="success", service="' + serviceName + '", ha="true"}[1m]) > 0.75',
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
        ],
      },
    ],
  },
};


{
  GenGenericAlertingRule: genGenericAlertingRule,
}
