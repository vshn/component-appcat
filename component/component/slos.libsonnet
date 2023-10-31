// main template for openshift4-slos
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';


local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.appcat;

local alertsDisabled = !inv.parameters.appcat.slos.alertsEnabled;

local newSLO(name, group, sloParams) =
  {
    local slo = self,

    name: name,
    objective: sloParams.objective,
    alerting: {
      labels: params.slos.alerting.labels,
      page_alert: {
        labels: params.slos.alerting.page_labels,
        annotations: {
          [if std.objectHas(slo.alerting.page_alert, 'for') then 'for']: std.get(slo.alerting.page_alert, 'for'),
        },
      },
      ticket_alert: {
        labels: params.slos.alerting.ticket_labels,
        annotations: {
          [if std.objectHas(slo.alerting.ticket_alert, 'for') then 'for']: std.get(slo.alerting.ticket_alert, 'for'),
          runbook_url: 'https://hub.syn.tools/appcat/runbooks/%s.html#%s' % [ group, name ],
        },
      },
    } + com.makeMergeable(sloParams.alerting),
  } + com.makeMergeable(
    std.get(sloParams, 'sloth', default={})
  );

local prometheusRule(name) =
  local slothRendered = std.parseJson(kap.yaml_load('%s/sloth-output/%s.yaml' % [ inv.parameters._base_directory, name ]));

  local patchedRules = slothRendered {
    groups: [
      g {
        rules: [ r {
          [if std.objectHas(r, 'annotations') && std.objectHas(r.annotations, 'for') then 'for']: std.get(super.annotations, 'for'),
        } for r in g.rules ],
      }
      for g in super.groups
      if !(alertsDisabled && std.startsWith(g.name, 'sloth-slo-alerts'))
    ],
  };

  kube._Object('monitoring.coreos.com/v1', 'PrometheusRule', kube.hyphenate(name)) {
    metadata+: {
      namespace: params.slos.namespace,
    },
    spec: patchedRules,
  };

{
  slothInput: {
    'vshn-postgresql': [
      newSLO('uptime', 'vshn-postgresql', params.slos.vshn.postgres.uptime) {
        description: 'Uptime SLO for PostgreSQL by VSHN',
        sli: {
          events: {
            // The  0*rate(...) makes sure that the query reports an error rate for all instances, even if that instance has never produced a single error
            error_query: '(sum(rate(appcat_probes_seconds_count{reason!="success", service="VSHNPostgreSQL", ha="false"}[{{.window}}]) or 0*rate(appcat_probes_seconds_count{service="VSHNPostgreSQL"}[{{.window}}])) by (service, namespace, name, organization, sla) or vector(0)) - scalar(appcat:cluster:maintenance) > 0 or sum(0*rate(appcat_probes_seconds_count{service="VSHNPostgreSQL"}[{{.window}}])) by (service, namespace, name, organization, sla)',
            total_query: 'sum(rate(appcat_probes_seconds_count{service="VSHNPostgreSQL", ha="false"}[{{.window}}])) by (service, namespace, name, organization, sla)',
          },
        },
        alerting+: {
          name: 'SLO_AppCat_VSHNPostgreSQLUptime',
          annotations+: {
            summary: 'Probes to PostgreSQL by VSHN instance fail',
          },
          labels+: {
            service: 'VSHNPostgreSQL',
            OnCall: '{{ if eq $labels.sla "guaranteed" }}true{{ else }}false{{ end }}',
          },
        },
      },
    ],
    'vshn-postgresql-ha': [
      newSLO('uptime', 'vshn-postgresql-ha', params.slos.vshn.postgres.uptime) {
        description: 'Uptime SLO for High Available PostgreSQL by VSHN',
        sli: {
          events: {
            // The  0*rate(...) makes sure that the query reports an error rate for all instances, even if that instance has never produced a single error
            error_query: 'sum(rate(appcat_probes_seconds_count{reason!="success", service="VSHNPostgreSQL", ha="true"}[{{.window}}]) or 0*rate(appcat_probes_seconds_count{service="VSHNPostgreSQL"}[{{.window}}])) by (service, namespace, name, organization, sla) or sum(0*rate(appcat_probes_seconds_count{service="VSHNPostgreSQL"}[{{.window}}])) by (service, namespace, name, organization, sla)',
            total_query: 'sum(rate(appcat_probes_seconds_count{service="VSHNPostgreSQL", ha="true"}[{{.window}}])) by (service, namespace, name, organization, sla)',
          },
        },
        alerting+: {
          name: 'SLO_AppCat_HAVSHNPosgtreSQLUptime',
          annotations+: {
            summary: 'Probes to HA PostgreSQL by VSHN instance fail',
          },
          labels+: {
            service: 'VSHNPostgreSQL',
            OnCall: '{{ if eq $labels.sla "guaranteed" }}true{{ else }}false{{ end }}',
          },
        },
      },
    ],
    // redis without HA
    'vshn-redis': [
      newSLO('uptime', 'vshn-redis', params.slos.vshn.redis.uptime) {
        description: 'Uptime SLO for Redis by VSHN',
        sli: {
          events: {
            // The  0*rate(...) makes sure that the query reports an error rate for all instances, even if that instance has never produced a single error
            error_query: '(sum(rate(appcat_probes_seconds_count{reason!="success", service="VSHNRedis", ha="false"}[{{.window}}]) or 0*rate(appcat_probes_seconds_count{service="VSHNRedis"}[{{.window}}]))  by (service, namespace, name, organization, sla) or vector(0)) - scalar(appcat:cluster:maintenance) > 0 or sum(0*rate(appcat_probes_seconds_count{service="VSHNRedis"}[{{.window}}])) by (service, namespace, name, organization, sla)',
            total_query: 'sum(rate(appcat_probes_seconds_count{service="VSHNRedis", ha="false"}[{{.window}}])) by (service, namespace, name, organization, sla)',
          },
        },
        alerting+: {
          name: 'SLO_AppCat_VSHNRedisUptime',
          annotations+: {
            summary: 'Probes to Redis by VSHN instance fail',
          },
          labels+: {
            service: 'VSHNRedis',
            OnCall: '{{ if eq $labels.sla "guaranteed" }}true{{ else }}false{{ end }}',
          },
        },
      },
    ],
    'vshn-redis-ha': [
      newSLO('uptime', 'vshn-redis-ha', params.slos.vshn.redis.uptime) {
        description: 'Uptime SLO for High Available Redis by VSHN',
        sli: {
          events: {
            // The  0*rate(...) makes sure that the query reports an error rate for all instances, even if that instance has never produced a single error
            error_query: '(sum(rate(appcat_probes_seconds_count{reason!="success", service="VSHNRedis", ha="true"}[{{.window}}]) or 0*rate(appcat_probes_seconds_count{service="VSHNRedis"}[{{.window}}]))  by (service, namespace, name, organization, sla) or vector(0)) - scalar(appcat:cluster:maintenance) > 0 or sum(0*rate(appcat_probes_seconds_count{service="VSHNRedis"}[{{.window}}])) by (service, namespace, name, organization, sla)',
            total_query: 'sum(rate(appcat_probes_seconds_count{service="VSHNRedis", ha="true"}[{{.window}}])) by (service, namespace, name, organization, sla)',
          },
        },
        alerting+: {
          name: 'SLO_AppCat_HAVSHNRedisUptime',
          annotations+: {
            summary: 'Probes to HA Redis by VSHN instance fail',
          },
          labels+: {
            service: 'VSHNRedis',
            OnCall: '{{ if eq $labels.sla "guaranteed" }}true{{ else }}false{{ end }}',
          },
        },
      },
    ],
    'vshn-minio-ha': [
      newSLO('uptime', 'vshn-minio-ha', params.slos.vshn.minio.uptime) {
        description: 'Uptime SLO for High Available Minio by VSHN',
        sli: {
          events: {
            // The  0*rate(...) makes sure that the query reports an error rate for all instances, even if that instance has never produced a single error
            error_query: '(sum(rate(appcat_probes_seconds_count{reason!="success", service="VSHNMinio", ha="true"}[{{.window}}]) or 0*rate(appcat_probes_seconds_count{service="VSHNMinio"}[{{.window}}]))  by (service, namespace, name, organization, sla) or vector(0)) - scalar(appcat:cluster:maintenance) > 0 or sum(0*rate(appcat_probes_seconds_count{service="VSHNMinio"}[{{.window}}])) by (service, namespace, name, organization, sla)',
            total_query: 'sum(rate(appcat_probes_seconds_count{service="VSHNMinio", ha="true"}[{{.window}}])) by (service, namespace, name, organization, sla)',
          },
        },
        alerting+: {
          name: 'SLO_AppCat_HAVSHNMinioUptime',
          annotations+: {
            summary: 'Probes to HA Minio by VSHN instance fail',
          },
          labels+: {
            service: 'VSHNMinio',
            OnCall: '{{ if eq $labels.sla "guaranteed" }}true{{ else }}false{{ end }}',
          },
        },
      },
    ],
    // minio without HA
    'vshn-minio': [
      newSLO('uptime', 'vshn-minio', params.slos.vshn.minio.uptime) {
        description: 'Uptime SLO for Minio by VSHN',
        sli: {
          events: {
            // The  0*rate(...) makes sure that the query reports an error rate for all instances, even if that instance has never produced a single error
            error_query: '(sum(rate(appcat_probes_seconds_count{reason!="success", service="VSHNMinio", ha="false"}[{{.window}}]) or 0*rate(appcat_probes_seconds_count{service="VSHNMinio"}[{{.window}}]))  by (service, namespace, name, organization, sla) or vector(0)) - scalar(appcat:cluster:maintenance) > 0 or sum(0*rate(appcat_probes_seconds_count{service="VSHNMinio"}[{{.window}}])) by (service, namespace, name, organization, sla)',
            total_query: 'sum(rate(appcat_probes_seconds_count{service="VSHNMinio", ha="false"}[{{.window}}])) by (service, namespace, name, organization, sla)',
          },
        },
        alerting+: {
          name: 'SLO_AppCat_VSHNMinioUptime',
          annotations+: {
            summary: 'Probes to Minio by VSHN instance fail',
          },
          labels+: {
            service: 'VSHNMinio',
            OnCall: '{{ if eq $labels.sla "guaranteed" }}true{{ else }}false{{ end }}',
          },
        },
      },
    ],
  },
  Get(name): prometheusRule(name),
}
