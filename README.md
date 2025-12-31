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

Blog Builder supports an optional Bluesky-based comment system that uses the AT Protocol. This provides a zero-maintenance, decentralized commenting solution where each blog post becomes a Bluesky thread.

### Configuration

Add the following to your `config.yaml`:

```yaml
at_proto:
  enabled: true
  service_identifier: "your-bot.bsky.social"  # Your Bluesky handle
  app_view_url: "https://public.api.bsky.app" # Optional, defaults to public API
  turnstile_site_key: "your-turnstile-key"    # Optional, for Cloudflare Turnstile captcha
```

### How It Works

1. **Build-time**: When you build your site, Blog Builder creates a Bluesky post for each new blog post and stores the AT URI in the frontmatter.
2. **Runtime**: Comments are loaded client-side from Bluesky's public API.
3. **Interaction**: Users reply via deep links to the Bluesky app.

### Frontmatter

After a post is announced to Bluesky, the `bluesky_uri` is automatically added to your post's frontmatter:

```yaml
---
title: My Blog Post
date: 2024-01-15
bluesky_uri: at://did:plc:xxx/app.bsky.feed.post/xxx
---
```

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
