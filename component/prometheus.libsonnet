local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local inv = kap.inventory();
local params = inv.parameters.appcat;


local promRecordingRuleSLA(value, service) = {
  expr: 'vector(' + value + ')',
  labels: {
    service: service,
  },
  record: 'sla:objective:ratio',
};

local bottomPod(query) = 'label_replace( bottomk(1, %(query)s) * on(namespace) group_left(label_appcat_vshn_io_claim_namespace) kube_namespace_labels, "name", "$1", "namespace", "vshn-replacemeplease-(.+)-.+")' % query;
local topPod(query) = 'label_replace( topk(1, %(query)s) * on(namespace) group_left(label_appcat_vshn_io_claim_namespace) kube_namespace_labels, "name", "$1", "namespace", "vshn-replacemeplease-(.+)-.+")' % query;

local generatePrometheusNonSLORules(serviceName, memoryContainerName, additionalAlertsRuleGroup) = {
  // standardized lowercase regardless of what came as input
  local serviceNameLower = std.asciiLower(serviceName),
  local toReplace = 'vshn-replacemeplease',
  local queries = {
    availableStorage: 'kubelet_volume_stats_available_bytes{job="kubelet", metrics_path="/metrics"}',
    availablePercent: '(%s / kubelet_volume_stats_capacity_bytes{job="kubelet", metrics_path="/metrics"})' % queries.availableStorage,
    usedStorage: 'kubelet_volume_stats_used_bytes{job="kubelet", metrics_path="/metrics"}',
    unlessExcluded: 'unless on(namespace, persistentvolumeclaim) kube_persistentvolumeclaim_access_mode{ access_mode="ReadOnlyMany"} == 1 unless on(namespace, persistentvolumeclaim) kube_persistentvolumeclaim_labels{label_excluded_from_alerts="true"} == 1',
  },
  name: 'prometheusrule',
  base: {

    apiVersion: 'kubernetes.crossplane.io/v1alpha2',
    kind: 'Object',
    metadata: {
      name: 'prometheusrule',
    },
    spec: {
      providerConfigRef: {
        name: 'kubernetes',
      },
      forProvider+: {
        manifest+: {
          apiVersion: 'monitoring.coreos.com/v1',
          kind: 'PrometheusRule',
          metadata: {
            name: '%s-rules' % serviceNameLower,
          },
          spec: {
            groups: [
              {
                name: '%s-storage' % serviceNameLower,
                rules: [
                  {

                    alert: serviceName + 'PersistentVolumeFillingUp',
                    annotations: {
                      description: 'The volume claimed by the instance {{ $labels.name }} in namespace {{ $labels.label_appcat_vshn_io_claim_namespace }} is only {{ $value | humanizePercentage }} free.',
                      runbook_url: 'https://runbooks.prometheus-operator.dev/runbooks/kubernetes/kubepersistentvolumefillingup',
                      summary: 'PersistentVolume is filling up.',
                    },
                    expr: std.strReplace(bottomPod('%(availablePercent)s < 0.03 and %(usedStorage)s > 0 %(unlessExcluded)s' % queries), toReplace, 'vshn-' + serviceNameLower),
                    'for': '1m',
                    labels: {
                      severity: 'critical',
                      syn_team: 'schedar',
                    },
                  },
                  {
                    alert: serviceName + 'PersistentVolumeFillingUp',
                    annotations: {
                      description: 'Based on recent sampling, the volume claimed by the instance {{ $labels.name }} in namespace {{ $labels.label_appcat_vshn_io_claim_namespace }} is expected to fill up within four days. Currently {{ $value | humanizePercentage }} is available.',
                      runbook_url: 'https://runbooks.prometheus-operator.dev/runbooks/kubernetes/kubepersistentvolumefillingup',
                      summary: 'PersistentVolume is filling up.',
                    },
                    expr: std.strReplace(bottomPod('%(availablePercent)s < 0.15 and %(usedStorage)s > 0 and predict_linear(%(availableStorage)s[6h], 4 * 24 * 3600) < 0  %(unlessExcluded)s' % queries), toReplace, 'vshn-' + serviceNameLower),
                    'for': '1h',
                    labels: {
                      severity: 'warning',
                    },
                  },
                ],
              },
              {
                name: std.asciiLower(serviceName) + '-memory',
                rules: [
                  {
                    alert: serviceName + 'MemoryCritical',
                    annotations: {
                      description: 'The memory claimed by the instance {{ $labels.name }} in namespace {{ $labels.label_appcat_vshn_io_claim_namespace }} has been over 85% for 2 hours.\n  Please reducde the load of this instance, or increase the memory.',
                      runbook_url: 'https://hub.syn.tools/appcat/runbooks/vshn-generic.html#MemoryCritical',
                      summary: 'Memory usage critical',
                    },
                    expr: std.strReplace(topPod('(max(container_memory_working_set_bytes{container="%s"}) without (name, id)  / on(container,pod,namespace)  kube_pod_container_resource_limits{resource="memory"} * 100) > 85') % memoryContainerName, toReplace, 'vshn-' + serviceNameLower),
                    'for': '120m',
                    labels: {
                      severity: 'critical',
                      syn_team: 'schedar',
                    },
                  },
                ],
              },
            ] + additionalAlertsRuleGroup,
          },
        },
      },
    },
  },
};

{
  GeneratePrometheusNonSLORules(serviceName, memoryContainerName, additionalAlertsRuleGroup):
    generatePrometheusNonSLORules(serviceName, memoryContainerName, additionalAlertsRuleGroup),
  PromRecordingRuleSLA(value, service):
    promRecordingRuleSLA(value, service),
  TopPod(query):
    topPod(query),
  BottomPod(query):
    bottomPod(query),
}
