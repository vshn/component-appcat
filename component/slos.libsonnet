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
          runbook_url: 'https://hub.syn.tools/appcat/runbooks/%s.html#%s' % [ std.rstripChars(group, '-ha'), name ],
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

local getEvents(serviceName) = {
  // The  0*rate(...) makes sure that the query reports an error rate for all instances, even if that instance has never produced a single error
  error_query: 'sum(rate(appcat_probes_seconds_count{reason!="success", service="' + serviceName + '", ha="false", maintenance="false"}[{{.window}}]) or 0*rate(appcat_probes_seconds_count{service="' + serviceName + '"}[{{.window}}])) by (service, claim_namespace, name, organization, sla)',
  total_query: 'sum(rate(appcat_probes_seconds_count{service="' + serviceName + '", ha="false"}[{{.window}}])) by (service, claim_namespace, name, organization, sla)',
};

local getEventsHA(serviceName) = {
  // The  0*rate(...) makes sure that the query reports an error rate for all instances, even if that instance has never produced a single error
  error_query: 'sum(rate(appcat_probes_seconds_count{reason!="success", service="' + serviceName + '", ha="true"}[{{.window}}]) or 0*rate(appcat_probes_seconds_count{service="' + serviceName + '"}[{{.window}}])) by (service, claim_namespace, name, organization, sla)',
  total_query: 'sum(rate(appcat_probes_seconds_count{service="' + serviceName + '", ha="true"}[{{.window}}])) by (service, claim_namespace, name, organization, sla)',
};

local generateSlothInput(name, uptime) =
  local nameLower = std.asciiLower(name);
  {
    ['vshn-%s' % nameLower]: [
      newSLO('uptime', 'vshn-' + nameLower, uptime) {
        description: 'Uptime SLO for ' + name + ' by VSHN',
        sli: {
          events: getEvents('VSHN' + name),
        },
        alerting+: {
          name: 'SLO_AppCat_VSHN' + name + 'Uptime',
          annotations+: {
            summary: 'Probes to ' + name + ' by VSHN instance fail',
          },
          labels+: {
            service: 'VSHN' + name,
          },
        },
      },
    ],
    ['vshn-%s-ha' % nameLower]: [
      newSLO('uptime', 'vshn-' + nameLower + '-ha', uptime) {
        description: 'Uptime SLO for High Available ' + name + ' by VSHN',
        sli: {
          events: getEventsHA('VSHN' + name),
        },
        alerting+: {
          name: 'SLO_AppCat_HAVSHN' + name + 'Uptime',
          annotations+: {
            summary: 'Probes to HA ' + name + ' by VSHN instance fail',
          },
          labels+: {
            service: 'VSHN' + name,
          },
        },
      },
    ],
  };
{
  slothInput: std.foldl(function(objOut, name) objOut + generateSlothInput(name, params.slos.vshn[name].uptime), std.objectFields(params.slos.vshn), {}),
  // When using the `server-side-apply` on argo, the empty `annotations` object will cause a diff.
  // This removes all empty fields recursively.
  Get(name): std.prune(prometheusRule(name)),
}
