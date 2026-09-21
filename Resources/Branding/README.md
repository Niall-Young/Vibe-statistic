# App identity

`Creature.svg` is the editable source of the app icon: a white tile with a black abstract inorganic creature and two small apertures. No raster image or generated robot artwork is used.

The icon build uses Core Graphics and the project's SVG path parser to render this SVG at every required macOS icon size. Source path fills are preserved. `AppBrand` reads the same SVG silhouette and makes the apertures transparent for the monochrome menu bar.
