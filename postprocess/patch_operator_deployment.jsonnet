local com = import 'lib/commodore.libjsonnet';
local inv = com.inventory();

local on_openshift4 = std.member([ 'openshift4', 'oke' ], inv.parameters.facts.distribution);
local run_as_user = {
  runAsUser: null,
};

local fixup(obj) =
  if std.type(obj) == 'object' && obj.kind == 'Deployment' then
    obj {
      spec+: {
        template+: {
          spec+: {
            containers: [
              c {
                securityContext+: run_as_user,
              }
              for c in obj.spec.template.spec.containers
            ],
            initContainers: if std.objectHas(obj.spec.template.spec, 'initContainers')
            then [
              c {
                securityContext+: run_as_user,
              }
              for c in obj.spec.template.spec.initContainers
            ]
            else null,
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
