local common = import 'common.libsonnet';
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local vars = import 'config/vars.jsonnet';
local crossplane = import 'lib/appcat-crossplane.libsonnet';

local inv = kap.inventory();
local facts = inv.parameters.facts;
local params = inv.parameters.appcat;
local appcatImage = params.images.functionAppcat;
local pntImage = params.images.functionpnt;

local getFunction(name, package, runtimeConfigName) = {
  apiVersion: 'pkg.crossplane.io/v1beta1',
  kind: 'Function',
  metadata: {
    name: std.strReplace(name, '/', '-'),
  },
  spec: {
    package: package,
    packagePullPolicy: params.pullPolicy,
    runtimeConfigRef: {
      name: runtimeConfigName,
    },
    skipDependencyResolution: true,
  },
};

local appcatRuntimeConfig = {
  apiVersion: 'pkg.crossplane.io/v1beta1',
  kind: 'DeploymentRuntimeConfig',
  metadata: {
    name: 'function-appcat',
  },
  spec: {
    deploymentTemplate: {
      spec: {
        selector: {},
        template: {
          spec:
            {
              containers: [
                {
                  name: 'package-runtime',
                  command: [ 'appcat' ],
                  args: [ 'functions' ],
                  securityContext: {},
                },
              ],
              securityContext: {},
              serviceAccountName: 'function-appcat',
            },
        },
      },
    },
  },
};

local appcatProxyRuntimeConfig = {
  apiVersion: 'pkg.crossplane.io/v1beta1',
  kind: 'DeploymentRuntimeConfig',
  metadata: {
    name: 'enable-proxy',
  },
  spec: {
    deploymentTemplate: {
      spec: {
        selector: {},
        template: {
          spec:
            {
              containers: [
                {
                  name: 'package-runtime',
                  command: [ 'appcat' ],
                  args: [ 'functions', '--proxymode' ],
                  securityContext: {},
                },
              ],
              securityContext: {},
              serviceAccountName: 'function-appcat',
            },
        },
      },
    },
  },
};

local appcatFunctionImage = appcatImage.registry + '/' + appcatImage.repository + ':';

local unescapedVersions = kap.file_read(inv.parameters._base_directory + '/hack/versionlist');
local versions = std.split(std.strReplace(unescapedVersions, '/', '_'), '\n');

// Generate an array with a single item that contains the current branch or tag
local currentFunction = [ getFunction(common.GetCurrentFunctionName(), appcatFunctionImage + std.strReplace(params.images.appcat.tag, '/', '_') + '-func', if !params.proxyFunction then 'function-appcat' else 'enable-proxy') ];

// Generate an array with all additional function branches specified
local branchFunctions = std.foldl(
  function(out, v) out + [ getFunction('function-appcat-' + std.strReplace(v, '.', '-'), appcatFunctionImage + std.strReplace(v, '/', '_') + '-func', if !params.proxyFunction then 'function-appcat' else 'enable-proxy') ],
  params.deploymentManagementSystem.additionalFunctionBranches,
  currentFunction
);

// Finally also generate an array of the last 5 tags
local appcat = std.prune(std.foldl(
  function(out, v)
    out + [
      if v != '' then
        local splitv = std.split(v, '-');
        getFunction('function-appcat-' + std.strReplace(v, '.', '-'), appcatFunctionImage + splitv[1] + '-func', if !params.proxyFunction then 'function-appcat' else 'enable-proxy'),
    ],
  versions,
  branchFunctions
));

local saAppCat = kube.ServiceAccount('function-appcat') {
  metadata+: {
    namespace: params.crossplane.namespace,
  },
};

local saPnT = kube.ServiceAccount('function-patch-and-transform') {
  metadata+: {
    namespace: params.crossplane.namespace,
  },
};

local pntFunctionImage = pntImage.registry + '/' + pntImage.repository + ':' + pntImage.tag;

assert !params.proxyFunction || params.proxyFunction && std.objectHas(facts, 'appcat_dev') && facts.appcat_dev : 'Proxy config only allowed for Dev environments!';

if vars.isSingleOrControlPlaneCluster then
  {
    '10_function_patch_and_transform': getFunction('function-patch-and-transform', pntFunctionImage, 'function-patch-and-transform'),
    // We filter out dupes, as it might happen that the initial version
    // and a generated version can be the same.
    '10_function_appcat': std.uniq(std.sort(appcat, function(x) x.metadata.name), function(x) x.metadata.name),
    '10_runtimeconfig_function_appcat': appcatRuntimeConfig,
    [if params.proxyFunction then '10_runtimeconfig_proxy_appcat']: appcatProxyRuntimeConfig,
    '10_runtimeconfig_function_pnt': common.DefaultRuntimeConfigWithSaName('function-patch-and-transform'),
    '20_serviceaccount_appcat': saAppCat,
    '20_serviceaccount_pnt': saPnT,
  } else {}
