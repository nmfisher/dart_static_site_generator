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
