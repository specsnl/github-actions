# One build job per platform, on the runner $override maps it to, or the default one.
({"linux/amd64": "ubuntu-26.04", "linux/arm64": "ubuntu-26.04-arm"} + $override) as $runners
| [.target[].platforms[]] | unique
| map({
    platform: .,
    slug: gsub("[^A-Za-z0-9]+"; "-"),
    runner: ($runners[.] // error("no runner for platform \(.); add it to the runners input"))
  })
