# The targets that build for $platform, as its build job builds them: narrowed to $platform, pushed by digest when
# $push is "true" and otherwise only to the cache, with a cache scope per image, target and platform. The tags are left
# out; the publish job tags the images.
def image: .tags[0] // "" | sub(":[^:/]*$"; "");

.target |= with_entries(
  select(.value.platforms | index($platform))
  | "\(.value | image | gsub("[^A-Za-z0-9]+"; "-"))-\(.key)-\($slug)" as $scope
  | .value |= (
      (if $push == "true" then
        "type=image,name=\(image),push-by-digest=true,name-canonical=true,oci-mediatypes=true,rewrite-timestamp=true,push=true"
      else
        "type=cacheonly"
      end) as $output
      | del(.tags, .load, .push)
      | .platforms = [$platform]
      | .output = [$output]
      | .["cache-from"] = ["type=gha,scope=\($scope)"]
      | .["cache-to"] = ["type=gha,mode=max,scope=\($scope)"]
    )
)
| .group = {default: {targets: (.target | keys)}}
