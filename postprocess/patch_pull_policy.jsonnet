local com = import 'lib/commodore.libjsonnet';
local inv = com.inventory();
local params = inv.parameters.appcat;

local pullPolicy(obj) =
  if std.type(obj) == 'object' && obj.kind == 'Deployment' then
    obj {
      spec+: {
        template+: {
          spec+: {
            containers: [
              c {
                imagePullPolicy: params.pullPolicy,
              }
              for c in obj.spec.template.spec.containers
            ],
            [if std.objectHas(obj.spec.template.spec, 'initContainers') then 'initContainers']: [
              c {
                imagePullPolicy: params.pullPolicy,
              }
              for c in obj.spec.template.spec.initContainers
            ],
          },
        },
      },
    }
  else if std.type(obj) == 'object' && obj.kind == 'StatefulSet' then
    obj {
      spec+: {
        template+: {
          spec+: {
            containers: [
              c {
                imagePullPolicy: params.pullPolicy,
              }
              for c in obj.spec.template.spec.containers
            ],
            [if std.objectHas(obj.spec.template.spec, 'initContainers') then 'initContainers']: [
              c {
                imagePullPolicy: params.pullPolicy,
              }
              for c in obj.spec.template.spec.initContainers
            ],
          },
        },
      },
    }
  else
    obj;

com.fixupDir(std.extVar('output_path'), pullPolicy)
