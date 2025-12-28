// lib/src/tools/at_proto_announcer.dart
import 'dart:io';
import 'package:bluesky/bluesky.dart' as bsky;
import 'package:yaml_edit/yaml_edit.dart';
import 'package:blog_builder/src/config_models.dart';
import 'package:blog_builder/src/page_models.dart';

/// AT Protocol announcer for creating and managing comment thread anchor posts
class AtProtoAnnouncer {
  final AtProtoConfig config;

  AtProtoAnnouncer({
    required this.config,
  });

  /// Check if a page needs an anchor post
  bool needsAnchorPost(PageModel page) {
    return page.atUri == null && !page.draft && !page.isIndex;
  }

  /// Ensure all pages have anchor posts, creating them if needed
  Future<List<PageModel>> ensureAnchorPosts({
    required List<PageModel> pages,
    required String baseUrl,
  }) async {
    if (!config.enabled) {
      print('AT Protocol comments disabled, skipping anchor post creation');
      return pages;
    }

    // Read credentials from environment variables (more secure than config file)
    final identifier = config.serviceIdentifier ?? Platform.environment['BSKY_IDENTIFIER'];
    final password = Platform.environment['BSKY_PASSWORD'];

    if (identifier == null || password == null) {
      print('Note: BSKY_IDENTIFIER/BSKY_PASSWORD not set, skipping anchor post creation');
      return pages;
    }

    // Find pages that need anchor posts
    final pagesToAnnounce = pages.where(needsAnchorPost).toList();

    if (pagesToAnnounce.isEmpty) {
      print('All pages already have anchor posts');
      return pages;
    }

    print('Creating anchor posts for ${pagesToAnnounce.length} pages...');

    bsky.Bluesky? session;
    try {
      session = await _authenticate(identifier, password);

      final updatedPages = <PageModel>[];
      for (final page in pages) {
        if (needsAnchorPost(page)) {
          try {
            print('Creating anchor post for: ${page.title}');
            final atUri = await _createAnchorPost(session, page, baseUrl);
            await _updateFrontmatter(page.source, atUri);
            updatedPages.add(page.copyWith(atUri: atUri));
            print('  ✓ Created: $atUri');
          } catch (e) {
            print('  ✗ Failed to create anchor post for ${page.title}: $e');
            updatedPages.add(page);
          }
        } else {
          updatedPages.add(page);
        }
      }

      return updatedPages;
    } catch (e) {
      print('Error authenticating with AT Protocol: $e');
      return pages;
    }
  }

  /// Authenticate with the PDS using service credentials
  Future<bsky.Bluesky> _authenticate(String identifier, String password) async {
    final sessionResponse = await bsky.createSession(
      identifier: identifier,
      password: password,
      service: 'bsky.social',
    );

    final session = await bsky.Bluesky.fromSession(sessionResponse.data);

    print('Authenticated as $identifier');
    return session;
  }

  /// Create an anchor post for comments
  Future<String> _createAnchorPost(
    bsky.Bluesky session,
    PageModel page,
    String baseUrl,
  ) async {
    // Ensure baseUrl doesn't end with /
    final cleanBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;

    final canonicalUrl = '$cleanBaseUrl${page.route}';

    // Create post text with link
    final text = 'Comments for: ${page.title}\n$canonicalUrl';

    // Create facets for the URL
    final urlStart = text.indexOf(canonicalUrl);
    final urlEnd = urlStart + canonicalUrl.length;

    final facets = [
      bsky.Facet(
        index: bsky.ByteSlice(
          byteStart: urlStart,
          byteEnd: urlEnd,
        ),
        features: [
          bsky.FacetFeature.link(
            data: bsky.FacetLink(uri: canonicalUrl),
          ),
        ],
      ),
    ];

    final response = await session.feed.createPost(
      text: text,
      facets: facets,
    );

    return response.data.uri.toString();
  }

  /// Update the markdown file's frontmatter with the AT URI
  Future<void> _updateFrontmatter(String sourcePath, String atUri) async {
    final file = File(sourcePath);
    final content = await file.readAsString();

    // Parse frontmatter boundaries (handle both Unix \n and Windows \r\n line endings)
    final frontmatterMatch = RegExp(r'^---\r?\n([\s\S]*?)\r?\n---').firstMatch(content);
    if (frontmatterMatch == null) {
      print('Warning: No frontmatter found in $sourcePath, skipping at_uri update');
      return;
    }

    final frontmatterStr = frontmatterMatch.group(1)!;

    // Check if at_uri already exists
    if (frontmatterStr.contains('at_uri:')) {
      print('  → at_uri already exists, skipping');
      return;
    }

    final editor = YamlEditor(frontmatterStr);
    editor.update(['at_uri'], atUri);

    final updatedFrontmatter = editor.toString();

    // Preserve original line ending style
    final lineEnding = content.contains('\r\n') ? '\r\n' : '\n';

    final newContent = content.replaceFirst(
      frontmatterMatch.group(0)!,
      '---$lineEnding$updatedFrontmatter---',
    );

    await file.writeAsString(newContent);
  }
}
