# OnSpeak website

Static landing page for OnSpeak.

## Files

- `index.html` - landing page with SEO metadata, structured data, and the main UI.
- `assets/app-icon.png` - optimized app icon used by the page and social metadata.
- `assets/demo.gif` - product demo shown above the fold.
- `llms.txt` - concise project summary for AI agents and answer engines.
- `robots.txt` - crawler policy and sitemap pointer.
- `sitemap.xml` - sitemap for `https://hrushikesh-thorat.github.io/OnSpeak/`.

## Deploy

Published to GitHub Pages by `.github/workflows/pages.yml`, which uploads this
directory as the Pages artifact on every push to `main` that touches `website/`.
The live URL is `https://hrushikesh-thorat.github.io/OnSpeak/`.

To point a custom domain here later, add a `CNAME` file (containing the domain)
to this directory, set the domain under **Settings -> Pages -> Custom domain**,
and update the absolute URLs in `index.html`, `sitemap.xml`, `robots.txt`, and
`llms.txt` back to that domain.
