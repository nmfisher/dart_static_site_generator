# AT Comments Widget

The source is `src/at_comments.js`. The site builder ships the compiled widget
from `../lib/src/defaults/assets/js/at_comments.js`.

```sh
npm ci
npm run build
npm test
```

The build uses esbuild and updates both the shipped JavaScript and the local
bundle, including their source maps. Tests
check both the source and shipped bundle for safe handling of comment text.

Enable the widget with `at_proto.enabled: true` in the site configuration. The
bundled post layout passes page and site data to the comments partial. Custom
layouts can use:

```liquid
{% render '_includes/comments.liquid', page: page, site: site %}
```

The widget reads threads through the configured Bluesky AppView and submits
comments to `/api/comment`, which must be provided by the hosting application.
