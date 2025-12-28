# AT Comments Widget Build

This directory contains the source code and build configuration for the AT Protocol comments widget that uses the official `@atproto/oauth-client-browser` library.

## Structure

- `src/at_comments.js` - Source code for the comments widget
- `package.json` - Dependencies and build script
- `node_modules/` - Installed dependencies (not committed to git)

## Building

The bundled JavaScript is already pre-built and located at:
`../lib/src/defaults/assets/js/at_comments.js`

To rebuild after making changes:

```bash
cd js-build
npm install  # Only needed first time or after package.json changes
npm run build
```

This will bundle the source code with all dependencies into a single IIFE file that can be included in HTML.

## Dependencies

- `@atproto/oauth-client-browser` - Official AT Protocol OAuth client with DPoP support
- `@atproto/api` - AT Protocol API client (Agent class)
- `esbuild` - Fast JavaScript bundler

## Output

The build produces:
- `at_comments.js` (~1.9MB) - Bundled widget with all dependencies
- `at_comments.js.map` - Source map for debugging

The large size is due to including the complete OAuth implementation with DPoP support, crypto libraries, and AT Protocol client.

## Usage

The widget is automatically included when `at_proto.enabled: true` in your blog's `config.yaml`.

In your templates, initialize it with:

```javascript
window.atCommentsInstance = new AtComments.AtCommentsWidget(
  'comments-container',
  postUri,
  appViewUrl,
  clientId
);
await window.atCommentsInstance.load();
```

## OAuth Configuration

The widget uses OAuth client metadata at `/.well-known/oauth-client-metadata.json` which is automatically generated during the blog build process.
