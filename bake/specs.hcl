# Shared tag, label and annotation rules for images built with specsnl/github-actions bake.yml.
#
# Vendored: copy this file into the consuming repository unchanged and update it when you move bake.yml to a new
# version; the workflow warns when the copy differs. Build locally with:
#
#   docker buildx bake -f specs.hcl -f docker-bake.hcl
#
# The variables below are set by bake.yml's plan job. The defaults are what a local build gets.

variable "VERSION" {
  default = "dev"
}

# The GitHub event name, i.e. "push", "pull_request", "schedule" or "workflow_dispatch". Empty for a local build.
variable "EVENT" {
  default = ""
}

# "tag" or "branch".
variable "REF_TYPE" {
  default = ""
}

# The branch or tag name.
variable "REF_NAME" {
  default = ""
}

variable "PR_NUMBER" {
  default = ""
}

# The tag a workflow_dispatch run publishes under, already lowercased.
variable "DISPATCH_TAG" {
  default = "latest"
}

# "true" on a tag push whose version has no "-" in it. Only then do the moving tags (1.2, 1, latest) move.
variable "IS_STABLE" {
  default = "false"
}

variable "REVISION" {
  default = ""
}

variable "SOURCE" {
  default = ""
}

variable "CREATED" {
  default = ""
}

# The repository's name, description and SPDX license, the fallbacks for the title, description and licenses labels.
variable "REPOSITORY_NAME" {
  default = ""
}

variable "REPOSITORY_DESCRIPTION" {
  default = ""
}

variable "LICENSES" {
  default = ""
}

# The full tag list for a target: every image name crossed with the tags this run publishes. A non-empty variant is
# appended as a suffix ("1.2.3-alpine"), and on a stable release the bare variant name takes the place of "latest".
#
#   tags = specs_tags(["ghcr.io/specsnl/specs-cli"], "alpine")
function "specs_tags" {
  params = [images, variant]
  result = flatten([
    for image in images : [
      for tag in specs_tag_names(variant) : "${lower(image)}:${tag}"
    ]
  ])
}

# The tags without the image name, see specs_tags.
function "specs_tag_names" {
  params = [variant]
  result = concat(
    [for tag in _specs_base_tags() : _specs_sanitize(variant == "" ? tag : "${tag}-${variant}")],
    EVENT == "push" && REF_TYPE == "tag" && IS_STABLE == "true" ? [variant == "" ? "latest" : variant] : [],
  )
}

# The org.opencontainers.image.* labels: version, revision, source, url, created, licenses, and the given title and
# description. An empty title or description falls back to the repository's name or description. Empty values are
# left out rather than written as "".
#
#   labels = specs_labels("PHP 8.4", "")
function "specs_labels" {
  params = [title, description]
  result = {
    for key, value in {
      "org.opencontainers.image.version"     = VERSION
      "org.opencontainers.image.revision"    = REVISION
      "org.opencontainers.image.source"      = SOURCE
      "org.opencontainers.image.url"         = SOURCE
      "org.opencontainers.image.created"     = CREATED
      "org.opencontainers.image.licenses"    = LICENSES
      "org.opencontainers.image.title"       = title != "" ? title : REPOSITORY_NAME
      "org.opencontainers.image.description" = description != "" ? description : REPOSITORY_DESCRIPTION
    } : key => value if value != ""
  }
}

# The same values as specs_labels, as annotations on the platform image manifest. The publish job copies them onto the
# index and its descriptors.
#
#   annotations = specs_annotations("PHP 8.4", "")
function "specs_annotations" {
  params = [title, description]
  result = [for key, value in specs_labels(title, description) : "manifest:${key}=${value}"]
}

function "_specs_base_tags" {
  params = []
  result = (
    EVENT == "" ? ["local"] :
    EVENT == "push" && REF_TYPE == "tag" ? _specs_release_tags() :
    EVENT == "push" && REF_TYPE == "branch" ? [REF_NAME] :
    EVENT == "pull_request" || EVENT == "pull_request_target" ? ["pr-${PR_NUMBER}"] :
    EVENT == "schedule" ? ["nightly"] :
    EVENT == "workflow_dispatch" ? [DISPATCH_TAG] :
    []
  )
}

# 1.2.3, plus 1.2 unless it is 0.0.x and 1 unless it is 0.x. A prerelease, or a version that isn't semver, publishes
# only itself.
function "_specs_release_tags" {
  params = []
  result = (
    IS_STABLE == "true" && length(_specs_semver()) == 1 ? _specs_semver_tags(_specs_semver()[0]) : [VERSION]
  )
}

function "_specs_semver_tags" {
  params = [v]
  result = concat(
    ["${v[0]}.${v[1]}.${v[2]}"],
    v[0] == "0" && v[1] == "0" ? [] : ["${v[0]}.${v[1]}"],
    v[0] == "0" ? [] : [v[0]],
  )
}

function "_specs_semver" {
  params = []
  result = regexall("^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$", VERSION)
}

# A tag may only contain [A-Za-z0-9_.-], may not start with "." or "-", and is at most 128 characters.
function "_specs_sanitize" {
  params = [tag]
  result = substr(regex_replace(regex_replace(tag, "[^A-Za-z0-9_.-]", "-"), "^[.-]+", ""), 0, 128)
}
