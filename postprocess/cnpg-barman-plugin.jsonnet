local com = import 'lib/commodore.libjsonnet';
local inv = com.inventory();

local on_openshift4 = std.member([ 'openshift4', 'oke' ], inv.parameters.facts.distribution);

/* Remove runAsUser and runAsGroup from security context for OpenShift compatibility */
local removeUserGroupFromSecurityContext(securityContext) =
  std.prune({
    [k]: securityContext[k]
    for k in std.objectFields(securityContext)
    if k != 'runAsUser' && k != 'runAsGroup'
  });

/* Fix barman cloud plugin deployment for OpenShift */
local fixup(obj) =
  if std.type(obj) == 'object' && obj.kind == 'Deployment' && obj.metadata.name == 'plugin-barman-cloud' then
    obj {
      spec+: {
        template+: {
          spec+: {
            containers: [
              c {
                [if std.objectHas(c, 'securityContext') then 'securityContext']:
                  removeUserGroupFromSecurityContext(c.securityContext),
              }
              for c in obj.spec.template.spec.containers
            ],
          },
        },
      },
    }
  else
    obj;

if on_openshift4 then
  com.fixupDir(std.extVar('output_path'), fixup)
else
  {}
