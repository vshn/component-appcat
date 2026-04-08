local vars = import 'config/vars.jsonnet';
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local prometheus = import 'lib/prometheus.libsonnet';
local inv = kap.inventory();

local params = inv.parameters.appcat.cnpg;
local disabledAlerts = params.postgres.disabledAlerts;

local namespace =
  if params.monitoring.enabled && std.member(inv.applications, 'prometheus') then
    if params.monitoring.instance != null then
      prometheus.RegisterNamespace(kube.Namespace(params.namespace), params.monitoring.instance)
    else
      prometheus.RegisterNamespace(kube.Namespace(params.namespace))
  else
    kube.Namespace(params.namespace)
;

local name = 'cnpg';
local labels = {
  'app.kubernetes.io/name': name,
  'app.kubernetes.io/managed-by': 'commodore',
};

local prometheusrule = std.prune(kube._Object('monitoring.coreos.com/v1', 'PrometheusRule', 'cnpg-alerts') {
  metadata+: {
    namespace: inv.parameters.appcat.namespace,
    labels: labels,
  },
  spec: {
    groups: [ {
      name: 'cnpg-ha-alerts',
      rules: std.filter(
        function(rule) !std.member(disabledAlerts, rule.alert),
        [
          {
            alert: 'CNPGPostgreSQLReplicationLagCritical',
            expr: 'cnpg_pg_replication_lag > 300',
            'for': '5m',
            labels: {
              severity: 'critical',
              service: 'cnpg-postgres',
              syn: 'true',
              syn_team: 'schedar',
              syn_component: 'appcat',
              OnCall: 'false',
            },
            annotations: {
              summary: 'PostgreSQL replication lag critical',
              description: 'The replication lag to {{ $labels.pod }} in {{ $labels.namespace }} has been over 300 seconds for 5 minutes.\n  Please investigate the replication status of this instance.',
              runbook_url: 'https://kb.vshn.ch/app-catalog/service/postgresql/runbooks/CNPGPostgreSQLReplicationLagCritical.html',
            },
          },
          {
            alert: 'CNPGPostgreSQLReplicaFailingReplication',
            expr: 'cnpg_pg_replication_in_recovery == 1 and on(namespace, pod) cnpg_pg_replication_is_wal_receiver_up == 0',
            'for': '5m',
            labels: {
              severity: 'critical',
              service: 'cnpg-postgres',
              syn: 'true',
              syn_team: 'schedar',
              syn_component: 'appcat',
              OnCall: 'false',
            },
            annotations: {
              summary: 'PostgreSQL replica failing replication',
              description: 'A replica in {{ $labels.namespace }} is in recovery but the WAL receiver is not running.\n  Please investigate the replication status of this instance.',
              runbook_url: 'https://kb.vshn.ch/app-catalog/service/postgresql/runbooks/system/CNPGPostgreSQLReplicaFailingReplication.html',
            },
          },
          {
            alert: 'CNPGPostgreSQLManualSwitchoverRequired',
            expr: 'max by(namespace)(cnpg_collector_manual_switchover_required) == 1',
            'for': '1m',
            labels: {
              severity: 'critical',
              service: 'cnpg-postgres',
              syn: 'true',
              syn_team: 'schedar',
              syn_component: 'appcat',
              OnCall: '{{ if eq $labels.sla "guaranteed" }}true{{ else }}false{{ end }}',
            },
            annotations: {
              summary: 'PostgreSQL manual switchover required',
              description: 'A manual switchover is required for the PostgreSQL cluster in {{ $labels.namespace }}.\n  Please perform the switchover using the CNPG plugin.',
              runbook_url: 'https://kb.vshn.ch/app-catalog/service/postgresql/runbooks/system/CNPGPostgreSQLManualSwitchoverRequired.html',
            },
          },
          {
            alert: 'CNPGPostgreSQLNoStreamingReplicas',
            expr: 'cnpg_pg_replication_streaming_replicas == 0 and on(namespace, pod) cnpg_pg_replication_in_recovery == 0 and on(namespace) sum by(namespace)(cnpg_pg_replication_in_recovery) > 0',
            'for': '5m',
            labels: {
              severity: 'critical',
              service: 'cnpg-postgres',
              syn: 'true',
              syn_team: 'schedar',
              syn_component: 'appcat',
              OnCall: 'false',
            },
            annotations: {
              summary: 'PostgreSQL has no streaming replicas',
              description: 'The HA cluster in {{ $labels.namespace }} has no streaming replicas connected to the primary for 5 minutes.\n  HA is completely broken. If the primary fails now, there is no replica to promote.',
              runbook_url: 'https://kb.vshn.ch/app-catalog/service/postgresql/runbooks/system/CNPGPostgreSQLNoStreamingReplicas.html',
            },
          },
          {
            alert: 'CNPGPostgreSQLXIDWraparound',
            expr: 'cnpg_pg_database_xid_age > 300000000 and on(namespace, pod) cnpg_pg_replication_in_recovery == 0',
            'for': '1m',
            labels: {
              severity: 'critical',
              service: 'cnpg-postgres',
              syn: 'true',
              syn_team: 'schedar',
              syn_component: 'appcat',
              OnCall: '{{ if eq $labels.sla "guaranteed" }}true{{ else }}false{{ end }}',
            },
            annotations: {
              summary: 'PostgreSQL transaction ID wraparound risk',
              description: 'Database {{ $labels.datname }} in {{ $labels.namespace }} has a transaction ID age of {{ $value }}.\n  XID wraparound will cause PostgreSQL to shut down to prevent data corruption. Run VACUUM FREEZE immediately.',
              runbook_url: 'https://kb.vshn.ch/app-catalog/service/postgresql/runbooks/system/CNPGPostgreSQLXIDWraparound.html',
            },
          },
          {
            alert: 'CNPGPostgreSQLFencingOn',
            expr: 'cnpg_collector_fencing_on == 1',
            'for': '1m',
            labels: {
              severity: 'critical',
              service: 'cnpg-postgres',
              syn: 'true',
              syn_team: 'schedar',
              syn_component: 'appcat',
              OnCall: 'false',
            },
            annotations: {
              summary: 'PostgreSQL instance is fenced',
              description: 'A PostgreSQL instance in {{ $labels.namespace }} has fencing enabled.\n  The instance is isolated from traffic and requires manual intervention using the CNPG plugin to unfence.',
              runbook_url: 'https://kb.vshn.ch/app-catalog/service/postgresql/runbooks/system/CNPGPostgreSQLFencingOn.html',
            },
          },
          {
            alert: 'CNPGPostgreSQLArchiveFailing',
            expr: 'cnpg_pg_stat_archiver_last_failed_time > cnpg_pg_stat_archiver_last_archived_time and cnpg_pg_stat_archiver_last_archived_time > 0',
            'for': '5m',
            labels: {
              severity: 'warning',
              service: 'cnpg-postgres',
              syn: 'true',
              syn_team: 'schedar',
              syn_component: 'appcat',
              OnCall: 'false',
            },
            annotations: {
              summary: 'PostgreSQL WAL archiving is failing',
              description: 'WAL archiving for the PostgreSQL cluster in {{ $labels.namespace }} has been failing.\n  Point-in-time recovery and backups are at risk. Investigate the archive_status and object store connectivity.',
              runbook_url: 'https://kb.vshn.ch/app-catalog/service/postgresql/runbooks/system/CNPGPostgreSQLArchiveFailing.html',
            },
          },
          {
            alert: 'CNPGClusterHAWarning',
            expr: 'max by (namespace) (cnpg_pg_replication_streaming_replicas) < 2 and on(namespace) sum by (namespace) (cnpg_pg_replication_in_recovery) > 0',
            'for': '5m',
            labels: {
              severity: 'warning',
              service: 'cnpg-postgres',
              syn: 'true',
              syn_team: 'schedar',
              syn_component: 'appcat',
              OnCall: 'false',
            },
            annotations: {
              summary: 'CNPG Cluster High Availability warning',
              description: 'The cluster in {{ $labels.namespace }} has fewer than 2 streaming replicas. HA is degraded.',
              runbook_url: 'https://github.com/cloudnative-pg/charts/blob/main/charts/cluster/docs/runbooks/CNPGClusterHAWarning.md',
            },
          },
          {
            alert: 'CNPGClusterOffline',
            expr: 'count by(namespace)(cnpg_collector_up) == 0',
            'for': '5m',
            labels: {
              severity: 'critical',
              service: 'cnpg-postgres',
              syn: 'true',
              syn_team: 'schedar',
              syn_component: 'appcat',
              OnCall: '{{ if eq $labels.sla "guaranteed" }}true{{ else }}false{{ end }}',
            },
            annotations: {
              summary: 'CNPG Cluster is offline',
              description: 'All CNPG collectors in {{ $labels.namespace }} are reporting down. The cluster may be offline.',
              runbook_url: 'https://github.com/cloudnative-pg/charts/blob/main/charts/cluster/docs/runbooks/CNPGClusterOffline.md',
            },
          },
          {
            alert: 'CNPGClusterInstancesOnSameNode',
            expr: 'count by (namespace, node) (kube_pod_info{namespace=~"vshn-postgresql-.*",pod=~"postgresql-.*"} * on(pod,namespace) group_right(node) kube_pod_labels{label_cnpg_io_cluster=~".+"}) > 1',
            'for': '5m',
            labels: {
              severity: 'warning',
              service: 'cnpg-postgres',
              syn: 'true',
              syn_team: 'schedar',
              syn_component: 'appcat',
              OnCall: 'false',
            },
            annotations: {
              summary: 'CNPG Cluster instances on same node',
              description: 'Multiple CNPG instances in {{ $labels.namespace }} are running on the same node {{ $labels.node }}. This reduces HA effectiveness.',
              runbook_url: 'https://github.com/cloudnative-pg/charts/blob/main/charts/cluster/docs/runbooks/CNPGClusterInstancesOnSameNode.md',
            },
          },
          {
            alert: 'CNPGClusterZoneSpreadWarning',
            expr: 'count by(namespace)(kube_pod_info{namespace=~"vshn-postgresql-.*", pod=~"postgresql-.*"} * on(pod,namespace) group_right(node) kube_pod_labels{label_cnpg_io_cluster=~".+"}) > on(namespace) count by(namespace)(count by(namespace, label_topology_kubernetes_io_zone)(kube_pod_info{namespace=~"vshn-postgresql-.*", pod=~"postgresql-.*"} * on(node) group_left(label_topology_kubernetes_io_zone) kube_node_labels)) unless on(namespace) ALERTS{alertname="CNPGClusterInstancesOnSameNode", alertstate="firing"}',
            'for': '5m',
            labels: {
              severity: 'warning',
              service: 'cnpg-postgres',
              syn: 'true',
              syn_team: 'schedar',
              syn_component: 'appcat',
              OnCall: 'false',
            },
            annotations: {
              summary: 'CNPG Cluster zone spread warning',
              description: 'CNPG instances in {{ $labels.namespace }} are not evenly spread across availability zones. Some zones have multiple instances.',
              runbook_url: 'https://github.com/cloudnative-pg/charts/blob/main/charts/cluster/docs/runbooks/CNPGClusterZoneSpreadWarning.md',
            },
          },
        ]
      ),
    } ],
  },
});

local netpol = std.prune(kube._Object('networking.k8s.io/v1', 'NetworkPolicy', 'allow-webhook-all-namespaces') {
  metadata+: {
    namespace: params.namespace,
    labels: labels,
  },
  spec+: {
    policyTypes: [
      'Ingress',
    ],
    ingress: [
      {
        ports: [
          {
            port: 9443,
            protocol: 'TCP',
          },
        ],
      },
    ],
    podSelector: {
      matchLabels: {
        'app.kubernetes.io/name': 'cloudnative-pg',
      },
    },
  },
});

if params.enabled then
  {
    '00_namespace': namespace {
      metadata+: {
        labels+: params.namespaceLabels,
        annotations+: params.namespaceAnnotations,
      },
    },
    '10_cnpg_prometheusrule': prometheusrule,
    '11_networkpolicy': netpol,
  }
else {}
