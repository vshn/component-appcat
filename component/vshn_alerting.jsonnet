local kap = import 'lib/kapitan.libjsonnet';

local inv = kap.inventory();
local params = inv.parameters.appcat;
local vars = import 'config/vars.jsonnet';

local getRedisHARules(serviceName) = [
  {
    alert: 'VSHNRedisNotMaster',
    annotations: {
      description: 'Service {{ $labels.service }} is not connected to a master for 5m.',
      summary: 'Redis not master: {{ $labels.name }} ({{ $labels.namespace }})',
    },
    expr: 'appcat_probes_redis_ha_master_up{ha="true"} == 0',
    'for': '5m',
    labels: {
      OnCall: '{{ if eq $labels.sla "guaranteed" }}true{{ else }}false{{ end }}',
      service: serviceName,
      severity: 'critical',
      syn: 'true',
      syn_team: 'schedar',
      syn_component: 'appcat',
    },
  },
  {
    alert: 'VSHNRedisQuorumNotOk',
    annotations: {
      description: 'Quorum failing for 5m.',
      summary: 'Redis quorum not OK: {{ $labels.name }} ({{ $labels.namespace }})',
    },
    expr: |||
      appcat_probes_redis_ha_master_up{ha="true"} == 1
      and on(service,namespace,name,organization,ha,sla)
      appcat_probes_redis_ha_quorum_ok{ha="true"} == 0
    |||,
    'for': '5m',
    labels: {
      OnCall: false,
      service: serviceName,
      severity: 'warning',
      syn: 'true',
      syn_team: 'schedar',
      syn_component: 'appcat',
    },
  },
  {
    alert: 'VSHNRedisQuorumFlapping',
    annotations: {
      description: 'Quorum state flipped {{ $value }} times in 10m.',
      summary: 'Redis quorum flapping: {{ $labels.name }} ({{ $labels.namespace }})',
    },
    expr: |||
      appcat_probes_redis_ha_master_up{ha="true"} == 1
      and on(service,namespace,name,organization,ha,sla)
      changes(appcat_probes_redis_ha_quorum_ok{ha="true"}[10m]) >= 4
    |||,
    labels: {
      OnCall: false,
      service: serviceName,
      severity: 'warning',
      syn: 'true',
      syn_team: 'schedar',
      syn_component: 'appcat',
    },
  },
];

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
        ] + (if recordingRule != null then [ recordingRule ] else []) +
          (if serviceName == 'VSHNRedis' then getRedisHARules(serviceName) else []),
      },
    ],
  },
};


if params.slos.alertsEnabled && vars.isSingleOrServiceCluster then {
  GenGenericAlertingRule: genGenericAlertingRule,
} else {}
