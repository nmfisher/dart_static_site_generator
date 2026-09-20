# Blog Builder

A Dart static site generator using Markdown, YAML frontmatter, and Liquify templates.

## Quick start

```sh
dart pub get
dart run bin/blog_builder.dart --input example_blog --output build --no-announce
dart run bin/blog_builder.dart check --input example_blog
dart run bin/blog_builder.dart --input example_blog --serve --drafts
```

The default input is `example_blog`; the default output is `build`. A site contains:

```text
site/
  config.yaml
  content/
    index.md
    posts/hello.md
    projects/demo.md
  templates/              # Optional overrides of bundled templates
    _layouts/post.liquid
    _includes/header.liquid
  assets/                 # Copied into output/assets/
```

Templates and the basic stylesheet have bundled defaults. Override individual files
without copying an entire theme. `layout: post` resolves `_layouts/post.liquid`.

## Commands and preview

| Option | Behavior |
| --- | --- |
| `build` (default) | Generate the site into a staging directory, then replace output |
| `check` | Render in memory and report errors without writing output, cache, or frontmatter |
| `--input`, `-i` | Source directory |
| `--output`, `-o` | Generated site directory |
| `--serve` | Watch and serve with live reload; defaults to `http://127.0.0.1:8080` |
| `--watch`, `-w` | Watch and rebuild without starting a server |
| `--drafts` | Include unpublished content in pages, archives, and search |
| `--host`, `--port` | Preview bind address and port |
| `--no-incremental` | Disable persistent cache reads and writes |
| `--no-announce` | Disable build-time Bluesky anchor-post creation |
| `--help`, `-h` | Show command usage |

Watch and preview builds are serialized; edits arriving during a build trigger one
follow-up build. A failed rebuild leaves the previous site available and shows an
error notice in the browser. Successful rebuilds reload connected pages. Drafts,
watching, serving, and `check` always suppress Bluesky announcements.

Builds preserve the previous output on parsing, rendering, asset-processing, or
writing failures. Successful builds remove stale pages and assets. Publication uses
sibling staging and backup directories with rollback on rename failure; the two
renames can briefly leave the output path absent. Use a separate output directory:
it cannot overlap the input, content, templates, assets, or cache directories.

`check` reports duplicate routes, conflicting output paths, missing templates,
invalid frontmatter, missing local images/assets, broken internal links, and missing
anchors. It checks generated HTML, including `srcset`, without fetching external
URLs or executing JavaScript. CSS URLs and data-URI `srcset` lists are not checked.
Links outside a configured base path are treated as outside this site. It exits
nonzero on errors. `check --drafts` includes drafts in validation.

## Content and configuration

```yaml
---
title: My first post
date: 2026-09-16
layout: post
published: true
tags: [Dart, Templates]
categories: [Engineering]
priority: 1
meta:
  description: A short summary
  og:image: /assets/cover.png
---

## Getting started

Your Markdown and Liquid content goes here.
```

`published` must be a YAML boolean; unpublished or omitted values are drafts.
Dates use ISO 8601. Tags/categories accept lists or comma-separated strings.
Additional frontmatter is available as `page.<field>`. Set `route` (or `url`) to
override the path derived from the filename. `index.md` creates its directory's
index page; absent indexes are generated automatically.

```yaml
title: My site
owner: Your name
baseUrl: https://example.com/docs/
# base_path: /docs          # Defaults to the path portion of baseUrl
collections:
  posts:
    title: Posts
    layout: post
    page_size: 10
  projects:
    path: projects
    title: Projects
    layout: post
    page_size: 6
pagination:
  page_size: 10             # Default collection and taxonomy page size
search:
  enabled: true
markdown:
  highlight: true
  heading_anchors: true
  toc: true
rss:
  enabled: true
  file_name: feed.xml
  layouts: [post]
```

Collections group files under their configured content path. Explicit frontmatter
`collection` can select a different group. Each configured collection gets an
archive (`/projects/`) and subsequent pages (`/projects/page/2/`). A manual collection
index retains its content and receives paginated `page.children` data; use
`layout: list` to render the bundled listing. Tags and categories generate archives
such as `/tags/dart/` and `/categories/engineering/`, also paginated. Conflicting
slugs or routes fail the build.

Items sort by ascending `priority`, then newest date, then route. Collections expose
`site.collections.projects.all` and `.count`; taxonomies expose `site.tags.Dart`
and `site.categories.Engineering`. Existing directory lookups such as
`site.posts.all` and `site.posts.hello` remain available.

## Templates, URLs, and SEO

Layouts use Liquify inheritance; partials use scoped `render` arguments:

```liquid
{% layout '_layouts/default.liquid' %}
{% block content %}
  <h1>{{ page.title | escape }}</h1>
  {{ page.toc }}
  {{ content }}
  {% render '_includes/pagination.liquid', page: page, site: site %}
{% endblock %}
```

Content is rendered as Liquid, converted from Markdown, then inserted into the
layout. Layout HTML itself is not processed as Markdown.

| Value | Contents |
| --- | --- |
| `content`, `page.rendered_content` | Rendered page body |
| `page.toc`, `page.headings` | TOC HTML and heading records (`id`, `title`, `level`) |
| `page.previous`, `page.next` | Adjacent collection items in display order, with title and route |
| `page.pagination` | `page`, `total_pages`, `total_items`, `page_size`, `previous`, `next`, `pages` |
| `page.canonical_url`, `page.seo` | Canonical URL and social metadata |
| `page.formatted_date`, `page.long_date` | Preformatted date strings |

Use `relative_url` for mounted paths and `absolute_url` for full URLs:

```liquid
<a href="{{ page.route | relative_url }}">{{ page.title | escape }}</a>
{{ '/assets/cover.png' | absolute_url }}
{% render '_includes/seo.liquid', page: page, site: site %}
```

The filters also work inside rendered partials. With the configuration above,
`/posts/hello/` becomes `/docs/posts/hello/` or
`https://example.com/docs/posts/hello/`. Root-relative HTML links, image sources,
forms, posters, and `srcset` entries are mounted automatically. External URLs and
fragment links are preserved; already-mounted paths are not prefixed twice. Use
filters or explicit paths for URLs embedded in CSS or JavaScript. RSS and sitemap
URLs include the base path. Files still live directly in the output directory;
serve or deploy that directory at the configured mount point.

The default layout includes canonical, description, Open Graph, and Twitter tags.
Custom layouts can render the SEO partial explicitly. Set `baseUrl` for absolute
canonical URLs, RSS, and a sitemap.

## Markdown and search

Fenced code blocks with a recognized language receive syntax highlighting;
unknown languages remain escaped code. Headings receive stable, unique anchors.
The bundled post layout displays the TOC; custom layouts can insert `page.toc`.
Include `/assets/css/site.css` in fully custom layouts for the bundled styling.
Each Markdown feature can be disabled independently in configuration.

Search is enabled by default and generates `/search/`, `/search-index.json`, and
`/assets/js/search.js`. It searches rendered text, titles, and tags entirely in the
browser, ranks title matches first, and supports `/search/?q=your+query`. It excludes
index pages and drafts unless `--drafts` is used. Disable it with
`search.enabled: false` if you want to supply your own `/search/` page.

## Multi-language sites

Declare a `default_locale` plus a `locales` map in `config.yaml` to build each
locale as its own rooted site. The default locale stays at the site root; every
other locale builds under `/<locale>/...` (localized home, search page and
search index, RSS feed at `/<locale>/feed.xml` with its own `<language>`, and
collection archives). Translations are matched by identical relative path under
`content/<locale>/` and cross-linked automatically:

```yaml
default_locale: en
locales:
  en: { name: English }
  de: { name: Deutsch }
```

With `content/posts/hello.md` and a German translation in
`content/de/posts/hello.md`, the builder emits `/posts/hello/` and
`/de/posts/hello/`, adds hreflang `link rel="alternate"` tags plus an
`x-default` link to every page, lists both in a single sitemap via
`xhtml:link` entries, and points each locale's search page at its own
`/<locale>/search-index.json`. Pages can also set `locale:` in frontmatter
directly. Build a single locale with `blog_builder build --locale de`
(default-locale pages are then omitted). Untranslated pages still appear in
each locale's search index and feed, pointing at the default-locale URL.

### Template variables

When i18n is enabled, templates can inspect the page's locale and cross-links:

- `page.locale` — the locale code this page variant belongs to (`"en"`,
  `"de"`, ...). Unset on default-locale pages, so
  `{% if page.locale == 'de' %}` is the usual switch.
- `page.long_date` renders in the page's locale (ticket 004): `en`
  "July 15, 2026", `de` "15. Juli 2026", `zh` "2026年7月15日", plus the other
  built-in patterns (`ja`, `fr`, `es`, `pt`, `it`, `nl`, `ko`, `ru`; BCP 47
  subtags like `zh-CN` use the primary language). Unmapped locales keep the
  English format. `page.formatted_date` stays ISO `yyyy-MM-dd` in every
  locale, so `<time datetime=...>` output is locale-independent.
- `page.extras.alternates` — map of locale code -> route for every existing
  translation of the page (including its own locale). The bundled
  `seo.liquid` renders these as hreflang links; custom heads can iterate it
  directly:

  ```liquid
  {% for pair in page.extras.alternates %}
  <link rel="alternate" hreflang="{{ pair[0] }}" href="{{ pair[1] | absolute_url }}">
  {% endfor %}
  ```

- `site.i18n.enabled` / `site.i18n.default.code` — whether more than one
  locale is configured, and the default locale's code (useful for
  `hreflang="x-default"`).
- `site.<collection>` — locale-scoped (ticket 002): on a page whose locale is
  `L`, top-level collection drops resolve from the `/L/<collection>` subtree
  first, so `site.shop.all` lists the translated products with their `/L/...`
  routes. A collection that has no `L` entries (missing or empty subtree)
  falls back to the default-locale drop, so partially translated sites never
  go empty. The same scoping applies to `site.collections.<name>.all` /
  `.count` and to the per-locale archive pages. Default-locale pages always
  see the default drops.

Note that `{% render %}` isolates scope: an include only sees `page.locale`
if the caller passes it explicitly, e.g.
`{% render '_includes/footer.liquid' with page: page %}`. Includes rendered
without `page:` silently render default-locale output.

## Migrating templates to liquify 1.6.x

The liquify 1.6.1 upgrade (required for i18n builds) changed template
parsing in two observable ways:

1. **Triple-brace output `{{{ var }}}` no longer parses.** Layout analysis
   fails with `Failed to analyze layout template`. Rewrite as `{{ var }}`:
   liquify 1.6.x renders `{{ content }}` (and other raw-HTML values)
   unescaped, so output is identical. Search templates for `{{{` and replace
   every occurrence. (Real case: a consumer's `news_article.liquid` used
   `{{{ content }}}` and stopped building until rewritten; output verified
   unchanged after the rewrite.)
2. **Collection drops aggregate their sub-collections.** `site.<collection>.all`
   holds the collection's direct pages **plus every page in nested
   sub-directories** (`site.shop.all` on a shop with `blender/` and
   `unreal/` sub-directories lists all of them, sorted by the usual
   priority/date rule). Child drops stay exclusive: `site.shop.blender.all`
   is still exactly the blender pages. This matches the `all_*` convention
   of Shopify's collection object ("total ... in a collection", not a
   filtered subset) and Jekyll's flat recursive collections. Note the
   contrast with liquify 1.3.x, where the bare route-tree drop listed only
   direct children while the catalog drop (`site.collections.shop.all`)
   aggregated; the two surfaces now agree on aggregation.

Also new: generated index pages for directories inside `content/<locale>/`
are suppressed — add explicit `index.md` files if you want locale sub-index
pages.

## Incremental builds

The cache lives under `<input>/.blog-cache/v1/`. It stores parsed pages, rendered
content/layouts, and processed assets. Content hashes detect edits, including
changes whose file timestamps have not advanced. Layout and partial dependencies,
accessed site data, configuration, and image options invalidate affected entries.
Templates using the date values `'now'` or `'today'` are rendered afresh. Every build
assembles a complete staging directory so deletions never leave stale output.

The cache persists across CLI invocations. Delete `.blog-cache` to reclaim space;
it is disposable and excluded from watching. Add it to your site's ignore rules.
`--no-incremental` provides a clean comparison without reading or updating it.

## Image Optimization

Blog Builder includes built-in image optimization for PNG, JPEG, and WebP formats. Enable it in your `config.yaml`:

```yaml
image_optimization:
  enabled: true
  png:
    enabled: true
    compression_level: 9    # 0-9, higher = more compression
    strip_metadata: true
  jpeg:
    enabled: true
    quality: 85             # 0-100
  webp:
    enabled: true
    quality: 80             # 0-100
    method: 4               # 0-6, compression method/speed tradeoff
    create_fallbacks: true  # Keep original format alongside WebP
```

### WebP Conversion

When `webp.enabled` is `true`, PNG and JPEG images are automatically converted to WebP format. The `create_fallbacks` option keeps the original format for browsers that don't support WebP.

**Note:** WebP conversion requires `cwebp` to be installed on your system:
- macOS: `brew install webp`
- Ubuntu/Debian: `apt-get install webp`
- Windows: Download from [Google's WebP page](https://developers.google.com/speed/webp/download)

## Bluesky Comment System

Blog Builder supports an optional Bluesky-based comment system that uses the AT Protocol. Each blog post gets a corresponding Bluesky "anchor post", and blog comments appear as replies to that post.

### Configuration

Add the following to your `config.yaml`:

```yaml
at_proto:
  enabled: true
  service_identifier: "your-bot.bsky.social"  # Bluesky handle used to create anchor posts
  app_view_url: "https://public.api.bsky.app" # Optional, defaults to public API
  turnstile_site_key: "your-turnstile-key"    # Cloudflare Turnstile site key for comment captcha
```

### How It Works

1. **Build-time**: For published posts missing an `at_uri`, Blog Builder creates a Bluesky anchor post and writes the AT URI back into the frontmatter.
2. **Runtime**: The comments widget loads the reply thread from Bluesky's public API.
3. **Comment posting**: Handled server-side (e.g. via a Cloudflare Pages Function) which authenticates to Bluesky and creates reply records.

### Environment Variables

Anchor post creation requires these environment variables at build time:

- `BSKY_PASSWORD` — App-specific password for the account specified in `service_identifier`
- `BSKY_IDENTIFIER` — Optional, overrides `service_identifier` from config

### Frontmatter

The `at_uri` field is added automatically to your post's frontmatter after the anchor post is created. You can also set it manually — for example, if you already have a Bluesky post you want to use:

```yaml
---
title: My Blog Post
date: 2024-01-15
layout: post
published: true
at_uri: at://did:plc:xxx/app.bsky.feed.post/xxx
---
```

**Important:** The `at_uri` must be in AT Protocol URI format (`at://did:plc:.../app.bsky.feed.post/...`), not a Bluesky web URL. To convert a Bluesky URL like `https://bsky.app/profile/handle.bsky.social/post/abc123` to an `at_uri`:

1. Resolve the handle to a DID: `curl -s "https://bsky.social/xrpc/com.atproto.identity.resolveHandle?handle=handle.bsky.social"`
2. Assemble the URI: `at://did:plc:XXXXX/app.bsky.feed.post/abc123`

**Note:** Do not include `at_uri:` with an empty value in frontmatter. An empty `at_uri:` will be treated as present-but-empty and the announcer will skip the post silently. Either omit the field entirely or provide a valid value.

### Template Integration

Include the comments partial in your post template:

```liquid
{% render '_includes/comments.liquid', page: page, site: site %}
```

### Benefits

- **Zero Maintenance**: No database or authentication system to manage
- **Built-in Moderation**: Leverages Bluesky's native moderation tools
- **Network Effects**: Comments appear in users' Bluesky timelines
- **Identity Verification**: Real user identities reduce spam

## Development checks

```sh
dart analyze
dart test
cd js-build && npm test
```

WebP integration tests require `cwebp`. The Dart suite covers failed-build
preservation, validation, template dependency invalidation, collections, URLs,
Markdown, search indexing, and the HTTP/SSE preview server. JavaScript tests cover
comment rendering and browser search behavior. Rebuild the comments bundle with
`npm run build` in `js-build` after changing its source.
