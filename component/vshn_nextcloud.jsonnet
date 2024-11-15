local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local common = import 'common.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.appcat;
local nextcloudParams = params.services.vshn.nextcloud;
local isOpenshift = std.startsWith(inv.parameters.facts.distribution, 'openshift') || inv.parameters.facts.distribution == 'oke';


local scc =
  {
    allowHostDirVolumePlugin: true,
    allowHostIPC: true,
    allowHostNetwork: true,
    allowHostPID: true,
    allowHostPorts: true,
    allowPrivilegeEscalation: false,
    allowPrivilegedContainer: true,
    allowedCapabilities: [
      'MKNOD',
      'CHOWN',
      'SYS_CHROOT',
      'FOWNER',
    ],
    apiVersion: 'security.openshift.io/v1',
    defaultAddCapabilities: [
      'MKNOD',
      'CHOWN',
      'SYS_CHROOT',
      'FOWNER',
    ],
    kind: 'SecurityContextConstraints',
    metadata: {
      name: 'appcat-collabora',
    },
    readOnlyRootFilesystem: false,
    runAsUser: {
      type: 'MustRunAsNonRoot',
    },
    seLinuxContext: {
      type: 'MustRunAs',
    },
  };

if params.services.vshn.enabled then {
  [if params.services.vshn.nextcloud.enabled && isOpenshift then '22_scc_appcat']: scc,
} else {}
