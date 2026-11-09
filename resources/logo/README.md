# ProcessLama brand assets

The masters in `../brand/` are vendored from the commit in
`../brand/manifest.json`. Source filenames retain the Meridian ID `mimameidr`.

Regenerate with `python3 scripts/generate-brand-assets.py`. To consume a new
committed brand revision, add `--source /path/to/brand`. The dependency-free
`--check` verifies master hashes, derivative hashes and PNG dimensions. Raster
generation requires `rsvg-convert` and ImageMagick's `magick`.

The rounded desktop master feeds the macOS fallback catalog, Windows ICO and
Linux icon, because those platforms apply no mask. The full-bleed app master
feeds the website set and Icon Composer. The small tile feeds 16 px icons. The staged
`iconapp_icon.icon` layers require Apple Icon Composer review before adoption;
Xcode continues to use the fallback AppIcon catalog.

Previous artwork remains in Git history. `layers/` contains historical process
tree layers and does not feed current builds.

After website CSS, JavaScript, icon or artwork changes, regenerate the download
page and the content hashes in both pages and `site.webmanifest` with `python3 scripts/lib/website_release.py render --data website/_data/releases.json --output website/releases.html`. Both HTML pages
then load the matching assets without waiting for browser cache expiry.
