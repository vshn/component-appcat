#!/usr/bin/env python3

from git import Repo
import os
import sys
import yaml

versionlist = sys.argv[1]
repo_path = sys.argv[2]

repo = Repo(repo_path)

try:
    os.remove(versionlist)
except FileNotFoundError:
    print("versionlist doesn't exist yet")

tags = sorted(repo.tags, key=lambda t: t.commit.committed_datetime, reverse=True)
git_cmd = repo.git

closest_tag_name = repo.git.describe("--tags").split("-")[0]
print("Found closest tag to current commit: %s" % closest_tag_name)

defaults_file = "class/defaults.yml"

# We loop through all tags, we only start to count when we're at the currently closest tag.
# This should avoid getting any "future" versions deployed alongside.
i = 0
with open(versionlist, "w") as versions:
    for tag in tags:
        if i == 5:
            break
        if tag.name == closest_tag_name or i > 0:
            print("considering tag: %s with hash: %s" % (tag.name, tag.commit))

            i = i + 1

            res = repo.git.show("%s:%s" % (tag.commit, defaults_file))
            parsed_defaults = yaml.safe_load(res)

            appcat_version = parsed_defaults["parameters"]["appcat"]["images"][
                "appcat"
            ]["tag"]

            versions.write("%s-%s\n" % (tag.name, appcat_version))
