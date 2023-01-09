#kubectl $1 -f packages/tests/golden/composition-vshn-postgresql/appcat/appcat/additionalResources.yaml
kubectl $1 -f packages/tests/golden/composition-vshn-postgresql/appcat/appcat/compositions.yaml
kubectl $1 -f packages/tests/golden/composite-vshn-postgresql/appcat/appcat/clusterRoles.yaml
kubectl $1 -f packages/tests/golden/composite-vshn-postgresql/appcat/appcat/composites.yaml
