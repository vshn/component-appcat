local com = import 'lib/commodore.libjsonnet';
local inv = com.inventory();

local on_openshift4 = std.member([ 'openshift4', 'oke' ], inv.parameters.facts.distribution);
local transform_redhat_image(image) = image + '-ubi-9';

/* Change operator image if on OpenShift */
local fixup(obj) =
  if std.type(obj) == 'object' && obj.kind == 'Deployment' then
    obj {
      spec+: {
        template+: {
          spec+: {
            containers: [
              c {
                image: transform_redhat_image(c.image),
                env: [
                  if e.name == 'OPERATOR_IMAGE_NAME' then
                    { name: e.name, value: transform_redhat_image(c.image) }
                  else
                    e
                  for e in c.env
                ],
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
