# The targets that build for $platform, narrowed to it, each with its own GitHub Actions cache scope.
.target |= with_entries(
  select(.value.platforms | index($platform))
  | ("\($publish[0][.key].image | gsub("[^A-Za-z0-9]+"; "-"))-\(.key)-\($slug)") as $scope
  | .value.platforms = [$platform]
  | .value["cache-from"] = ["type=gha,scope=\($scope)"]
  | .value["cache-to"] = ["type=gha,mode=max,scope=\($scope)"]
)
| .group = {default: {targets: (.target | keys)}}
