local kap = import 'lib/kapitan.libjsonnet';

local inv = kap.inventory();
local params = inv.parameters.appcat;
local vars = import 'config/vars.jsonnet';

assert std.isNumber(params.pinnedTagStaleDays) && params.pinnedTagStaleDays == std.floor(params.pinnedTagStaleDays) : 'pinnedTagStaleDays must be an integer, got: ' + params.pinnedTagStaleDays;

local pinnedTagStaleRule = {
  apiVersion: 'monitoring.coreos.com/v1',
  kind: 'PrometheusRule',
  metadata: {
    name: 'appcat-pinned-image-tag-stale',
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
        name: 'appcat-pinned-image-tag-stale',
        rules: [
          {
            alert: 'VSHNPinnedImageTagStale',
            annotations: {
              description: 'Service {{ $labels.kind }} "{{ $labels.name }}" in namespace "{{ $labels.exported_namespace }}" has a pinned image tag "{{ $labels.pin_image_tag }}" that has not been updated for {{ $value | humanizeDuration }}. The instance may be missing security updates. Please inform the customer.',
              summary: 'Pinned image tag not updated for {{ $labels.kind }}/{{ $labels.name }}',
              runbook_url: 'https://kb.vshn.ch/app-catalog/framework/runbooks/VSHNPinnedImageTagStale.html',
            },
            expr: '(time() - appcat_pinned_image_tag_set_timestamp) > (%d * 24 * 3600)' % params.pinnedTagStaleDays,
            'for': '1h',
            labels: {
              OnCall: 'false',
              severity: 'warning',
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

if params.slos.enabled && params.slos.alertsEnabled && vars.isSingleOrServiceCluster then {
  'sli_exporter/90_VSHNPinnedImageTagStale': pinnedTagStaleRule,
} else {}
