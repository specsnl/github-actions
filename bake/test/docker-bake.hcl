group "default" {
  targets = ["utils", "runtime", "builder", "cli"]
}

target "utils" {
  platforms   = ["linux/amd64", "linux/arm64"]
  tags        = specs_tags(["ghcr.io/specsnl/utils"], "")
  labels      = specs_labels("", "")
  annotations = specs_annotations("", "")
}

target "_php" {
  dockerfile = "Dockerfile.php"
  platforms  = ["linux/amd64", "linux/arm64"]
}

target "runtime" {
  inherits    = ["_php"]
  target      = "runtime"
  tags        = specs_tags(["ghcr.io/specsnl/php84"], "")
  labels      = specs_labels("PHP 8.4", "PHP 8.4 runtime")
  annotations = specs_annotations("PHP 8.4", "PHP 8.4 runtime")
}

target "builder" {
  inherits    = ["_php"]
  target      = "builder"
  tags        = specs_tags(["ghcr.io/specsnl/php84/builder"], "")
  labels      = specs_labels("PHP 8.4 builder", "")
  annotations = specs_annotations("PHP 8.4 builder", "")
}

target "cli" {
  name      = "cli-${variant}"
  matrix    = { variant = ["debian", "alpine"] }
  target    = variant
  platforms = ["linux/amd64", "linux/arm64"]
  args      = { SPECS_VERSION = VERSION }
  tags      = specs_tags(["ghcr.io/SpecsNL/specs-cli"], variant == "debian" ? "" : variant)
  labels    = specs_labels("specs-cli", "")
}
