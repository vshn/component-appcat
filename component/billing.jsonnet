// main template for appuio-reporting
local alerts = import 'billing_alerts.libsonnet';
local cronjob = import 'billing_cronjob.libsonnet';
local netPol = import 'billing_netpol.libsonnet';
local common = import 'common.libsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.appcat;
local paramsBilling = params.billing;

local formatImage = function(ref) '%(registry)s/%(repository)s:%(tag)s' % ref;

local addOns = [ 'nextcloud-office' ];

// escape any non-valid characters and replace them with -
local escape = function(str)
  std.join('',
           std.map(
             function(c)
               if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')) then c else '-'
             , str
           ));

local odooSecret = kube.Secret('odoo-credentials') {
  metadata+: {
    namespace: paramsBilling.namespace,
    labels+: cronjob.Labels,
  },
  stringData: {
    client_id: paramsBilling.odoo.oauth.clientID,
    client_secret: paramsBilling.odoo.oauth.clientSecret,
    token_endpoint: paramsBilling.odoo.oauth.url,
  },
};

local appuioControlSecret = kube.Secret('appuio-control-sa') {
  metadata+: {
    namespace: paramsBilling.namespace,
    labels+: cronjob.Labels,
  },
  stringData: {
    kubeconfig: paramsBilling.cloud.appuioControlKubeConfig,
  },
};

local commonEnv = std.prune([
  {
    name: 'AR_ODOO_OAUTH_TOKEN_URL',
    valueFrom: {
      secretKeyRef: {
        name: odooSecret.metadata.name,
        key: 'token_endpoint',
      },
    },
  },
  {
    name: 'AR_ODOO_OAUTH_CLIENT_ID',
    valueFrom: {
      secretKeyRef: {
        name: odooSecret.metadata.name,
        key: 'client_id',
      },
    },
  },
  {
    name: 'AR_ODOO_OAUTH_CLIENT_SECRET',
    valueFrom: {
      secretKeyRef: {
        name: odooSecret.metadata.name,
        key: 'client_secret',
      },
    },
  },
  {
    name: 'AR_ODOO_URL',
    value: paramsBilling.odoo.url,
  },
  {
    name: 'AR_PROM_URL',
    value: paramsBilling.prometheus.url,
  },
]);

local backfillCJ = function(name, query, sla, type, isAddOn)

  local orgId = if type == 'cloud' then paramsBilling.prometheus.cloud_org_id else paramsBilling.prometheus.managed_org_id;

  local typeDesc = if type == 'cloud' then 'APPUiO Cloud - Zone: ' else 'APPUiO Managed - Cluster: ';

  local itemDescJsonnet = 'local labels = std.extVar("labels"); "%s" %% labels' % '%(label_appcat_vshn_io_claim_name)s';

  local clusterID = if paramsBilling.enableMockOrgInfo then 'kind' else '%(cluster_id)s';

  local zoneOrCluster = if type == 'cloud' then paramsBilling.cloudZone else clusterID;

  local itemGroupDesc = typeDesc + zoneOrCluster + ' / Namespace: %(label_appcat_vshn_io_claim_namespace)s';

  local itemGroupDescJsonnet = 'local labels = std.extVar("labels"); "%s" %% labels' % itemGroupDesc;

  local instanceJsonnet = 'local labels = std.extVar("labels"); "%s" %% labels' % '%(cluster_id)s/%(label_appcat_vshn_io_claim_namespace)s/%(label_appcat_vshn_io_claim_name)s';

  local instanceAddOnJsonnet = 'local labels = std.extVar("labels"); "%s" %% labels' % '%(cluster_id)s/%(label_appcat_vshn_io_claim_namespace)s/%(label_appcat_vshn_io_claim_name)s/%(label_appcat_vshn_io_addon_name)s';

  local productID = 'appcat-vshn-%(name)s-%(sla)s' % { name: name, sla: sla };

  local jobEnv = function(isAddOn) std.prune([
    {
      name: 'AR_ORG_ID',
      value: orgId,
    },
    {
      name: 'AR_PRODUCT_ID',
      value: productID,
    },
    {
      name: 'AR_QUERY',
      value: query,
    },
    {
      name: 'AR_INSTANCE_JSONNET',
      value: if isAddOn then instanceAddOnJsonnet else instanceJsonnet,
    },
    if itemGroupDescJsonnet != null then {
      name: 'AR_ITEM_GROUP_DESCRIPTION_JSONNET',
      value: itemGroupDescJsonnet,
    },
    if itemDescJsonnet != null then {
      name: 'AR_ITEM_DESCRIPTION_JSONNET',
      value: itemDescJsonnet,
    },
    {
      name: 'AR_UNIT_ID',
      value: paramsBilling.instanceUOM,
    },
  ]);

  cronjob.CronJob('%(product)s-%(type)s' % { product: escape(productID), type: type }, 'backfill', {
    containers: [
      {
        name: 'backfill',
        image: formatImage(params.images.reporting),
        env+: commonEnv + jobEnv(isAddOn),
        command: [ 'sh', '-c' ],
        args: [
          'appuio-reporting report --timerange 1h --begin=$(date -d "now -3 hours" -u +"%Y-%m-%dT%H:00:00Z") --repeat-until=$(date -u +"%Y-%m-%dT%H:00:00Z")',
        ],
        resources: {},
      },
    ],
  }) {
    metadata+: {
      annotations+: {
        'product-id': productID,
      },
    },
    spec+: {
      jobTemplate+: {
        metadata+: {
          annotations+: {
            'product-id': productID,
          },
        },
      },
      failedJobsHistoryLimit: 3,
      successfulJobsHistoryLimit: 1,
    },
  };

local getManagedQuery = function(queryName)
  'sum_over_time(appcat:metering{label_appuio_io_billing_name="appcat-' + queryName + '",label_appcat_vshn_io_sla="%s", tenant_name!="APPUiO"}[59m:1m])/60';

local getCloudQuery = function(queryName)
  'sum_over_time(appcat:metering{label_appuio_io_billing_name="appcat-' + queryName + '",label_appcat_vshn_io_sla="%s", tenant_name="APPUiO"}[59m:1m])/60 * on(label_appuio_io_organization) group_left(sales_order) label_replace(appuio_control_organization_info{namespace="appuio-control-api-production"}, "label_appuio_io_organization", "$1", "organization", "(.*)")';

local getPermutations = function(cloudQuery, managedQuery)
  [
    {
      query: cloudQuery % 'besteffort',
      sla: 'besteffort',
      type: 'cloud',
    },
    {
      query: cloudQuery % 'guaranteed',
      sla: 'guaranteed',
      type: 'cloud',
    },
    {
      query: managedQuery % 'besteffort',
      sla: 'besteffort',
      type: 'managed',
    },
    {
      query: managedQuery % 'guaranteed',
      sla: 'guaranteed',
      type: 'managed',
    },
  ];

local generateCloudAndManaged = function(name, isAddOn)

  // For postgresql we have a missmatch between the label and the name in our definition.
  local queryName = if name == 'postgres' then name + 'ql' else name;

  local managedQuery = 'sum_over_time(appcat:metering{label_appuio_io_billing_name="appcat-' + queryName + '",label_appcat_vshn_io_sla="%s", tenant_name!="APPUiO"}[59m:1m])/60';
  local cloudQuery = 'sum_over_time(appcat:metering{label_appuio_io_billing_name="appcat-' + queryName + '",label_appcat_vshn_io_sla="%s", tenant_name="APPUiO"}[59m:1m])/60 * on(label_appuio_io_organization) group_left(sales_order) label_replace(appuio_control_organization_info{namespace="appuio-control-api-production"}, "label_appuio_io_organization", "$1", "organization", "(.*)")';

  local permutations = [
    {
      query: cloudQuery % 'besteffort',
      sla: 'besteffort',
      type: 'cloud',
    },
    {
      query: cloudQuery % 'guaranteed',
      sla: 'guaranteed',
      type: 'cloud',
    },
    {
      query: managedQuery % 'besteffort',
      sla: 'besteffort',
      type: 'managed',
    },
    {
      query: managedQuery % 'guaranteed',
      sla: 'guaranteed',
      type: 'managed',
    },
  ];

  std.flatMap(function(r) [ backfillCJ(name, r.query, r.sla, r.type, isAddOn) ], permutations);

local vshnServices = common.FilterServiceByBoolean('billing');
local billingCronjobs = std.flattenArrays(std.flatMap(function(r) [ generateCloudAndManaged(r.name, false) ], vshnServices));
local billingAddOnsCronjobs = std.flattenArrays(std.flatMap(function(addOn) [ generateCloudAndManaged(addOn, true) ], addOns));

{
  [if params.billingEnabled then 'billing/10_appuio_control_secret']: appuioControlSecret,
} + if paramsBilling.vshn.enableCronjobs then
  {
    [if std.length(std.filter(function(name) paramsBilling.network_policies.target_namespaces[name] == true, std.objectFields(paramsBilling.network_policies.target_namespaces))) > 0 then 'billing/01_netpol']: netPol.Policies,
    'billing/10_odoo_secret': odooSecret,
    'billing/11_backfill': billingCronjobs,
    'billing/12_backfill_addons': billingAddOnsCronjobs,
    [if paramsBilling.monitoring.enabled then 'billing/50_alerts']: alerts.Alerts,
  } else {}
