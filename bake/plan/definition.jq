# The targets as the build jobs build them: pushed by digest when $push is "true", otherwise only to the cache. The
# tags and cache settings are left out; the publish job tags the images, and each build job sets its own cache.
def image: .tags[0] | sub(":[^:/]*$"; "");

.target |= with_entries(
  if (.value.platforms // []) == [] then
    error("target \(.key) has no platforms; set platforms in the bake file")
  elif $push == "true" and (.value.tags // []) == [] then
    error("target \(.key) has no tags for this event, so there is nothing to push")
  else . end
)
| .target |= map_values(
    (if $push == "true" then
      "type=image,name=\(image),push-by-digest=true,name-canonical=true,oci-mediatypes=true,rewrite-timestamp=true,push=true"
    else
      "type=cacheonly"
    end) as $output
    | del(.tags, .output, .["cache-from"], .["cache-to"], .load, .push)
    | .output = [$output]
  )
| .group = {default: {targets: (.target | keys)}}
