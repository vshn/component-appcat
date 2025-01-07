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
    name: name,
  },
  spec: {
    package: package,
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

local unescapedVersions = importstr './hack/versionlist';
local versions = std.split(std.strReplace(unescapedVersions, '/', '_'), '\n');

local appcat = std.foldl(
  function(out, v)
    out + [
      if v != '' then
        getFunction('function-appcat-' + std.strReplace(v, '.', '-'), appcatFunctionImage + v + '-func', if !params.proxyFunction then 'function-appcat' else 'enable-proxy'),
    ],
  versions,
  [ getFunction('function-appcat-' + std.strReplace(params.images.appcat.tag, '.', '-'), appcatFunctionImage + params.images.appcat.tag + '-func', if !params.proxyFunction then 'function-appcat' else 'enable-proxy') ]
);

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
    '10_function_appcat': appcat,
    '10_runtimeconfig_function_appcat': appcatRuntimeConfig,
    [if params.proxyFunction then '10_runtimeconfig_proxy_appcat']: appcatProxyRuntimeConfig,
    '10_runtimeconfig_function_pnt': common.DefaultRuntimeConfigWithSaName('function-patch-and-transform'),
    '20_serviceaccount_appcat': saAppCat,
    '20_serviceaccount_pnt': saPnT,
  } else {}
