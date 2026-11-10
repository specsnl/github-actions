# Per target, what the publish job needs: the image name, its tags, the labels it copies into annotations, and the
# platforms it expects a digest for.
.target | map_values({
  image: (.tags[0] // "" | sub(":[^:/]*$"; "")),
  tags: (.tags // []),
  labels: (.labels // {}),
  platforms
})
