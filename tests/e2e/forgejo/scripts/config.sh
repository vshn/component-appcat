#!/bin/bash

set -exf

ns=$(kubectl -n "$NAMESPACE" get vshnforgejo forgejo-e2e -oyaml | yq -r '.status.instanceNamespace')

inline_secret=$(kubectl -n "$ns" get secret -l app=forgejo -o name | grep inline)
credentials_secret=$(kubectl -n "$ns" get secret -o name | grep credentials-secret | head -n 1)
username=$(kubectl -n "$ns" get $credentials_secret -o yaml | yq .data.username | base64 -d)
password=$(kubectl -n "$ns" get $credentials_secret -o yaml | yq .data.password | base64 -d)

# ---------------------
# Check APP_NAME in inline secret
app_name=$(kubectl -n "$ns" get $inline_secret -o yaml | yq '.data."_generals_"' | base64 -d | grep APP_NAME | cut -d "=" -f 2)
[[ $app_name == "forgejo-e2e" ]]

# ---------------------
# Ensure mailer.PROTOCOL cannot be set to a bad value
kubectl -n "$NAMESPACE" patch vshnforgejo forgejo-e2e --type merge -p '{"spec":{"parameters":{"service":{"forgejoSettings":{"config":{"mailer":{"PROTOCOL":"sendmail"}}}}}}}' && exit 1 || true

# ---------------------
# Actions test, should fail
ing=$(kubectl -n "$ns" get ing -o name | head -n 1)
host=$(kubectl -n "$ns" get $ing -o yaml | yq .spec.rules[0].host)
url="https://$host"
base_url="$url/api/v1"

# 1. Check if config even has actions disabled
actions_enabled=$(kubectl -n "$ns" get $inline_secret -o yaml | yq '.data.actions' | base64 -d | grep ENABLED | cut -d "=" -f 2 | tr '[:upper:]' '[:lower:]')
[[ $actions_enabled == "false" ]]

# 2. Create repo using API
payload='{"name": "my-repo"}'
curl -X POST -H "Content-Type: application/json" -u "$username:$password" -d "$payload" "$base_url/user/repos"

# 3. Check if actions are enabled for repo (must be false)
actions_state=$(curl -s -X GET -H "Content-Type: application/json" -u "$username:$password" -d "$payload" "$base_url/repos/$username/my-repo" | jq .has_actions)
[[ $actions_state == "false" ]]
