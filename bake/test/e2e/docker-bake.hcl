variable "IMAGE" {
  default = "ghcr.io/specsnl/github-actions/e2e"
}

group "default" {
  targets = ["app", "cli"]
}

target "_e2e" {
  context = "bake/test/e2e"
}

target "app" {
  inherits    = ["_e2e"]
  target      = "app"
  platforms   = ["linux/amd64", "linux/arm64"]
  secret      = ["id=e2e,env=E2E_SECRET"]
  tags        = specs_tags([IMAGE], "")
  labels      = specs_labels("e2e app", "End-to-end test image of specsnl/github-actions")
  annotations = specs_annotations("e2e app", "End-to-end test image of specsnl/github-actions")
}

target "cli" {
  name        = "cli-${variant}"
  matrix      = { variant = ["debian", "alpine"] }
  inherits    = ["_e2e"]
  target      = variant
  platforms   = variant == "debian" ? ["linux/amd64", "linux/arm64"] : ["linux/amd64"]
  args        = { E2E_VERSION = VERSION }
  tags        = specs_tags(["${IMAGE}-cli"], variant == "debian" ? "" : variant)
  labels      = specs_labels("e2e cli", "")
  annotations = specs_annotations("e2e cli", "")
}
