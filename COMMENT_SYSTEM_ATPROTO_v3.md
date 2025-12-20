# Implementation Plan: Bluesky-Native Comment System v3

## Repository Introduction

This repository contains **Blog Builder**, a Dart-based static site generator designed for creating fast, secure, and maintainable markdown blogs. The generator transforms markdown files with YAML frontmatter into static HTML sites, supporting features such as:

- **Template System**: Liquid-based templating with customizable layouts
- **Asset Management**: Automatic copying and optimization of assets including image compression and WebP conversion
- **Hierarchical Content**: Support for nested content structures with auto-generated index pages
- **SEO Optimization**: Automatic sitemap generation and metadata handling
- **Two-Pass Rendering**: Sophisticated rendering pipeline for complex template dependencies

The architecture is built around core components:
- `StaticSiteBuilder`: Main orchestrator that manages the build process
- `PageModel`: Represents content pages with frontmatter and metadata
- `ConfigModel`: Handles site-wide configuration
- Template engine using Liquid templates for flexible layouts

## Comment System Integration

This document outlines the implementation of a **Bluesky-native comment system** as an optional feature for Blog Builder. Unlike traditional comment systems that require databases, authentication systems, and ongoing maintenance, this approach leverages the AT Protocol (the protocol behind Bluesky) to create a decentralized, maintenance-free commenting solution.

### Why This Approach for Blog Builder?

1. **Zero Maintenance**: As a static site generator, Blog Builder prioritizes simplicity and security. Adding a traditional comment system would require:
   - Database setup and maintenance
   - User authentication systems
   - Security monitoring for spam/abuse
   - Regular updates and patching

   The Bluesky approach eliminates all these concerns while providing a robust commenting experience.

2. **Decentralized Philosophy**: Just as static sites represent a move away from server complexity, AT Protocol represents a move toward decentralized social infrastructure. This aligns perfectly with Blog Builder's philosophy of simple, secure, and independent web publishing.

3. **Performance**: Comments are loaded client-side from Bluesky's public APIs, meaning they don't impact the initial page load or the static nature of the site.

4. **Network Effects**: Comments posted through this system become part of the Bluesky social graph, potentially driving traffic back to the blog as users' followers see their interactions.

## Overview

The comment system implementation treats every blog post as a "Root" post on Bluesky, with comments as standard replies. This approach follows the senior engineer's recommended architecture from v2, providing significant simplifications over the initial custom AT Protocol approach.

## Key Changes from v1 to v2
- **Storage**: Changed from custom AT Protocol records to standard Bluesky posts/replies
- **Authentication**: Delegated to Bluesky app (deep links) instead of custom OAuth
- **Moderation**: Uses native Bluesky moderation tools instead of custom admin interface
- **Simplicity**: No database management, uses public APIs only

## Integration with Existing Architecture

The comment system is designed as an optional module that integrates seamlessly with Blog Builder's existing architecture:

### Build-Time Integration
- **StaticSiteBuilder Extension**: The comment system hooks into the existing build process, adding a Bluesky announcement step after content parsing but before rendering
- **Frontmatter Enhancement**: Extends the existing `PageModel` to include `bluesky_uri`, storing the link between blog posts and their Bluesky threads
- **Configuration**: Adds to the existing `ConfigModel` without breaking changes, making the feature opt-in

### Template System Integration
- **Liquid Templates**: Leverages the existing template engine to render comment sections
- **Asset Pipeline**: Uses the existing asset copying mechanism to include JavaScript and CSS files
- **Data Model**: Fits naturally into the template context alongside existing page data

### Non-Intrusive Design
- **Optional Feature**: Sites without Bluesky configuration continue to work unchanged
- **Graceful Degradation**: If Bluesky is unavailable, pages still render with a simple reply link
- **Performance**: Zero impact on initial page load or SEO, as comments load asynchronously

## Architecture Overview

### Components
1. **Storage Layer**: The public Bluesky network (AppView)
2. **Linkage Layer**: Build-time script that creates a "Root" post on Bluesky for every new article
3. **Display Layer**: Client-side JavaScript that fetches the thread from the public API
4. **Interaction Layer**: Deep-links to the Bluesky app for posting replies (delegated authentication)

## Implementation Plan

### Phase 1: Dependencies and Configuration Setup
**Objective**: Add required dependencies and extend the configuration system

#### Tasks:
1. **Update pubspec.yaml**
   ```yaml
   dependencies:
     bluesky: ^0.14.0
     yaml_edit: ^2.2.0    # To update frontmatter safely
     http: ^1.1.0         # For API calls
   ```

2. **Extend ConfigModel** (`lib/src/config_models.dart`)
   - Add `blueskyConfig` field to store Bluesky settings
   - Parse configuration from config.yaml
   ```dart
   class BlueskyConfig {
     final String? identifier;
     final String? password; // Use App Password
     final String? pdsUrl; // Defaults to bsky.social
     final bool enabled;

     BlueskyConfig({
       this.identifier,
       this.password,
       this.pdsUrl = 'https://bsky.social',
       this.enabled = false,
     });
   }
   ```

3. **Configuration Structure** (config.yaml)
   ```yaml
   bluesky:
     enabled: true
     identifier: "your-site.bsky.social"
     password: "${BSKY_PASSWORD}"  # Environment variable
     pds_url: "https://bsky.social"
   ```

### Phase 2: Build-Time Integration (The Linkage)
**Objective**: Automate the creation of a Bluesky thread for every blog post to establish a "Root" URI.

#### Tasks:
1. **Create Bluesky Announcer** (`lib/src/tools/bluesky_announcer.dart`)
   ```dart
   class BlueskyAnnouncer {
     final BlueskyConfig config;
     final FileSystem fileSystem;

     Future<void> announceNewPosts(Directory contentDir) async {
       // Scan for posts without bluesky_uri
       // Post to Bluesky
       // Update frontmatter with URI
     }

     Future<String?> createBlueskyPost(PageModel page) async {
       // Generate summary/card
       // Post to Bluesky
       // Return URI
     }
   }
   ```

2. **Extend PageModel** (`lib/src/page_models.dart`)
   - Add `blueskyUri` field to store the AT URI
   - Parse from frontmatter on load
   - Update `toMap()` to include bluesky_uri
   ```dart
   // In PageModel class
   final String? blueskyUri;

   // In factory PageModel.from
   final blueskyUri = doc["bluesky_uri"]?.toString();
   ```

3. **Integrate with StaticSiteBuilder** (`lib/src/static_site_builder.dart`)
   - Add Bluesky announcement step before rendering
   - Run only if config is enabled
   ```dart
   if (siteConfig.blueskyConfig?.enabled == true) {
     await _announceToBluesky(pages);
   }
   ```

### Phase 3: Client-Side Display
**Objective**: Fetch and render comments dynamically without rebuilding the site.

#### Tasks:
1. **Create JavaScript Assets** (`web/js/comments.js`)
   ```javascript
   class BlueskyComments {
     constructor(containerId, uri) {
       this.container = document.getElementById(containerId);
       this.uri = uri;
       this.apiEndpoint = "https://public.api.bsky.app/xrpc/app.bsky.feed.getPostThread";
     }

     async loadComments() {
       // Fetch from API
       // Parse and filter responses
       // Render threaded comments
     }

     renderThread(comments, parentElement) {
       // Recursive rendering for nested replies
     }
   }
   ```

2. **Create CSS Styles** (`web/css/comments.css`)
   - Clean, minimal design
   - Responsive layout
   - Threaded indentation
   - Dark mode support

3. **Template Integration**
   - Create comment template (`templates/comments.liquid`)
   - Include in post layout
   ```html
   <div id="comments-section" data-uri="{{ page.bluesky_uri }}"></div>
   <script src="/js/comments.js"></script>
   ```

### Phase 4: Asset Management and Build Process

#### Tasks:
1. **Update Asset Copying** (`StaticSiteBuilder._copyAssets`)
   - Ensure JS/CSS files are copied to build directory
   - Add to default assets if not present in user assets

2. **Create Default Templates** (`lib/src/defaults/templates/`)
   - Add comment section template
   - Add comment item template for nested rendering

3. **Template Variables**
   - Pass bluesky_uri to template context
   - Add comment count display option

### Phase 5: Error Handling and Fallbacks

#### Tasks:
1. **API Error Handling**
   - Network failures
   - Rate limiting
   - Invalid URIs
   - Private/deleted posts

2. **Graceful Degradation**
   - Show fallback message if comments can't load
   - Display reply link even if comments fail
   - No blocking of page rendering

3. **Development Mode**
   - Mock comments for local development
   - Debug logging toggle

## Technical Implementation Details

### File Structure
```
lib/
  src/
    tools/
      bluesky_announcer.dart     # Build-time posting
    config_models.dart           # Extended with BlueskyConfig
    page_models.dart             # Extended with bluesky_uri
    static_site_builder.dart     # Integration point

web/
  js/
    comments.js                  # Client-side display
  css/
    comments.css                 # Comment styling

lib/src/defaults/templates/
  comments.liquid               # Comment container template

tool/
  announce_posts.dart           # Standalone CLI tool
```

### Environment Variables
```bash
# Required for production
BSKY_PASSWORD=app-password-here

# Optional
BSKY_IDENTIFIER=site.bsky.social
BSKY_PDS_URL=https://bsky.social
```

### Security Considerations
1. **App Passwords Only**: Never use main account password
2. **No Private Keys**: Client-side code only uses public URIs
3. **Content Security**: Sanitize all user-generated content
4. **Rate Limiting**: Respect API limits and implement backoff

### Error Scenarios and Handling
1. **Post Not Found**: Display "Comments not available" with reply link
2. **Network Error**: Retry with exponential backoff
3. **Rate Limited**: Queue requests and retry after delay
4. **Invalid URI**: Fallback to showing only reply link

### Performance Optimizations
1. **Lazy Loading**: Load comments only when scrolled into view
2. **Caching**: Browser cache for comment data (5-minute TTL)
3. **Pagination**: Load threads in chunks for popular posts
4. **CDN**: Serve static JS/CSS from CDN in production

## Migration Strategy

### For New Sites
1. Enable in config.yaml
2. Run initial build to announce all existing posts
3. Deploy with comment templates

### For Existing Sites
1. Gradual rollout:
   - Phase 1: Enable for new posts only
   - Phase 2: Manually announce selected popular posts
   - Phase 3: Bulk announce remaining posts

### Legacy Comments
1. Keep existing comments in separate section
2. Clear labeling: "Legacy Comments" vs "Bluesky Comments"
3. Option to disable legacy system after migration

## Testing Plan

### Unit Tests
1. BlueskyAnnouncer functionality
2. Frontmatter parsing and updates
3. Configuration validation
4. URI generation and validation

### Integration Tests
1. End-to-end post announcement
2. Comment fetching and rendering
3. Error handling scenarios
4. Build process integration

### Manual Testing
1. Create test Bluesky account
2. Post comments and replies
3. Test moderation flows
4. Verify responsive design

## Deployment Considerations

### CI/CD Integration
```yaml
# Example GitHub Actions step
- name: Announce to Bluesky
  run: dart tool/announce_posts.dart
  env:
    BSKY_PASSWORD: ${{ secrets.BSKY_PASSWORD }}
  if: ${{ github.event_name == 'push' && github.ref == 'refs/heads/main' }}
```

### Monitoring
1. Track announcement success/failure
2. Monitor API rate limits
3. Log comment loading errors
4. Analytics on comment engagement

## Benefits Summary

1. **Zero Maintenance**: No database to manage or backup
2. **Built-in Moderation**: Leverage Bluesky's moderation tools
3. **Network Effects**: Comments appear in users' timelines
4. **Identity Verification**: Real user identities, reduced spam
5. **Cost Effective**: Free hosting and bandwidth
6. **Developer Friendly**: Simple implementation, no auth complexity

## Future Enhancements

### Phase 2 Features (Post-Launch)
1. **Comment Previews**: Show first N comments in HTML for SEO
2. **Webmention Support**: Accept replies from other federated platforms
3. **Comment Analytics**: Track engagement metrics
4. **Moderation Dashboard**: Simple web interface for bulk actions

### Advanced Features
1. **Multi-language Support**: Detect and handle language-specific content
2. **Rich Media**: Embed images, links in comments
3. **Thread Gating**: Limit replies to followed users
4. **Custom Domains**: Use custom PDS for self-hosting

## Conclusion

This implementation provides a robust, maintenance-free comment system that leverages the decentralized nature of Bluesky while simplifying the technical complexity. The architecture aligns with modern web development practices and provides significant benefits over traditional comment systems.

## Next Steps

1. Review and approve this implementation plan
2. Set up Bluesky test account and app password
3. Begin Phase 1 implementation (dependencies and config)
4. Create test suite for all components
5. Implement Phase 2 (build-time integration)
6. Develop client-side components
7. Test with real content and users
8. Deploy to production
9. Monitor and iterate based on feedback