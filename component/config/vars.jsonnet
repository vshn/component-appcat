local common = import 'common.libsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.appcat;
local cms = params.clusterManagementSystem;

local isOpenshift = std.startsWith(inv.parameters.facts.distribution, 'openshift') || inv.parameters.facts.distribution == 'oke';
local isSingleCluster = cms.controlPlaneCluster && cms.serviceCluster;
local isControlPlane = cms.controlPlaneCluster && !cms.serviceCluster;
local isServiceCluster = !cms.controlPlaneCluster && cms.serviceCluster;
local getSubObjects(obj) = [
  obj[key]
  for key in std.objectFields(obj)
  if std.type(obj[key]) == 'object'
];
local getVSHNServicesObject() = std.md5(
  std.manifestJson(
    std.foldl(
      function(acc, s)
        if s.enabled == true then acc + s else acc,
      getSubObjects(params.services.vshn),
      {}
    )
  )
);

local isServiceClusterOpenShift = if isControlPlane then params.services.vshn.isServiceClusterOpenshift else isOpenshift;

{
  isOpenshift: isOpenshift,
  isServiceCluster: isServiceCluster,
  isControlPlane: isControlPlane,
  isSingleCluster: isSingleCluster,
  isCMSValid: cms.controlPlaneCluster || cms.serviceCluster,
  isSingleOrControlPlaneCluster: isSingleCluster || isControlPlane,
  isSingleOrServiceCluster: isSingleCluster || isServiceCluster,
  isServiceClusterOpenShift: isServiceClusterOpenShift,
  isExoscale: inv.parameters.facts.cloud == 'exoscale',
  GetVSHNServicesObject(): getVSHNServicesObject(),
  assert (cms.controlPlaneKubeconfig == '' && isSingleCluster) || !isSingleCluster : 'clusterManagementSystem.controlPlaneKubeconfig should be empty for converged clusters',
  assert (cms.controlPlaneKubeconfig != '' && isServiceCluster) || (isSingleCluster || isControlPlane) : 'clusterManagementSystem.controlPlaneKubeconfig should not be empty for service clusters',
}
