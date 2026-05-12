# Blog Builder

A Dart-based static site generator for markdown blogs.

## Project Structure

-   `bin/blog_builder.dart`: Main executable script.
-   `lib/`: Contains the core library code.
    -   `src/config_models.dart`: Models for parsing `config.yaml`.
    -   `src/page_models.dart`: Models for parsing Markdown files with frontmatter.
    -   `src/template.dart`: Simple placeholder template engine.
    -   `src/sitemap_generator.dart`: Utility to generate `sitemap.xml` (optional).
    -   `blog_builder.dart`: Main library export file.
-   `pubspec.yaml`: Project dependencies and metadata.
-   `blog/`: Default input directory.
    -   `config.yaml`: Site-wide configuration.
    -   `content/`: Markdown source files (supports subdirectories).
    -   `templates/`: HTML template files (e.g., `default.html`, `post.html`).
    -   `assets/`: Static files (CSS, JS, images) to be copied.
-   `build/`: Default output directory for the generated site.

## Usage

1.  **Install Dependencies:**
    ```bash
    cd blog_builder
    dart pub get
    ```

2.  **Create Content:**
    -   Edit `blog/config.yaml` with your site settings.
    -   Add your HTML templates (like `default.html`) to `blog/templates/`.
    -   Add your markdown files (with YAML frontmatter) to `blog/content/`.
        Example frontmatter:
        ```yaml
        ---
        title: My First Post
        date: 2023-10-27
        layout: post # Optional: uses templates/post.html
        published: true # Set to false for drafts
        meta:
          description: A short summary for SEO
        ---

        Your markdown content starts here...
        ```
    -   Place static assets (CSS, images) in `blog/assets/`.

3.  **Build the Site:**
    ```bash
    dart run bin/blog_builder.dart --input=blog --output=build
    ```
    Or use defaults:
    ```bash
    dart run bin/blog_builder.dart
    ```

4.  **View Output:**
    The generated static site will be in the `build/` directory. You can serve this directory using a simple HTTP server.

## Options

-   `--input` (`-i`): Specify the input directory (default: `blog`).
-   `--output` (`-o`): Specify the output directory (default: `build`).
-   `--help` (`-h`): Show help message.

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
{% render 'comments' %}
```

### Benefits

- **Zero Maintenance**: No database or authentication system to manage
- **Built-in Moderation**: Leverages Bluesky's native moderation tools
- **Network Effects**: Comments appear in users' Bluesky timelines
- **Identity Verification**: Real user identities reduce spam
