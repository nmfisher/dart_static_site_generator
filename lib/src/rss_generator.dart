import 'package:intl/intl.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:xml/xml.dart';
import 'package:blog_builder/blog_builder.dart';

class RSSGenerator {
  // RFC 822 date format for RSS feeds
  static final String _rfc822Format = 'EEE, dd MMM yyyy HH:mm:ss Z';

  /// Generate RSS 2.0 feed from PageModel objects
  static Future<void> generateFromPageModels(
    List<PageModel> pages,
    ConfigModel config, {
    required String outFile,
    FileSystem fileSystem = const LocalFileSystem(),
  }) async {
    final baseUrl = config.baseUrl;
    if (baseUrl == null || baseUrl.isEmpty) {
      throw ArgumentError('baseUrl must be set in config to generate RSS feed');
    }

    // Filter pages according to RSS config
    List<PageModel> feedItems = pages.where((p) => !p.draft).toList();

    // Filter by layout if configured
    if (config.rss.layouts.isNotEmpty) {
      feedItems = feedItems
          .where((p) => config.rss.layouts.contains(p.layoutId))
          .toList();
    }

    // Only include pages with dates (typical for blog posts)
    feedItems = feedItems.where((p) => p.date != null).toList();

    // Sort by date (newest first)
    feedItems.sort((a, b) {
      final aDate = a.date ?? DateTime(1970);
      final bDate = b.date ?? DateTime(1970);
      return bDate.compareTo(aDate);
    });

    // Apply item limit if configured
    if (config.rss.itemLimit != null &&
        config.rss.itemLimit! > 0 &&
        feedItems.length > config.rss.itemLimit!) {
      feedItems = feedItems.take(config.rss.itemLimit!).toList();
    }

    // Build RSS XML
    final rss = _buildRssXml(feedItems, config, baseUrl);

    // Write to file
    try {
      final file = fileSystem.file(outFile);
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      await file.writeAsString(rss.toXmlString(pretty: true, indent: '  '));
      print('RSS feed generated successfully at $outFile (${feedItems.length} items)');
    } catch (e) {
      print('Error writing RSS feed file $outFile: $e');
      rethrow;
    }
  }

  /// Build the RSS XML document
  static XmlDocument _buildRssXml(
    List<PageModel> items,
    ConfigModel config,
    String baseUrl,
  ) {
    // Get feed-level info
    final feedTitle = config.rss.title ?? config.title ?? 'Site Feed';
    final feedDescription = config.rss.description ??
        config.metadata['og:description'] ??
        config.metadata['description'] ??
        '';
    final feedUrl = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    final feedSelfUrl = '$feedUrl${config.rss.fileName}';

    // Create root element with namespaces
    final rssElement = XmlElement(
      XmlName('rss'),
      [
        XmlAttribute(XmlName('version'), '2.0'),
        XmlAttribute(
          XmlName('xmlns:atom'),
          'http://www.w3.org/2005/Atom',
        ),
        XmlAttribute(
          XmlName('xmlns:content'),
          'http://purl.org/rss/1.0/modules/content/',
        ),
      ],
      [],
    );

    // Create channel element
    final channelElement = XmlElement(XmlName('channel'), [], [
      _createElement('title', feedTitle),
      _createElement('description', feedDescription),
      _createElement('link', feedUrl),
      // Atom self link
      XmlElement(
        XmlName('atom:link'),
        [
          XmlAttribute(XmlName('href'), feedSelfUrl),
          XmlAttribute(XmlName('rel'), 'self'),
          XmlAttribute(XmlName('type'), 'application/rss+xml'),
        ],
        [],
      ),
      _createElement(
        'lastBuildDate',
        _formatDate(DateTime.now().toUtc()),
      ),
      _createElement('generator', 'Blog Builder'),
    ]);

    // Add items
    for (final item in items) {
      channelElement.children.add(_buildItemElement(item, baseUrl));
    }

    rssElement.children.add(channelElement);

    return XmlDocument([rssElement]);
  }

  /// Build an RSS item element from a PageModel
  static XmlElement _buildItemElement(PageModel item, String baseUrl) {
    final itemUrl = '$baseUrl${item.route}';
    final itemLink = itemUrl.endsWith('/') ? itemUrl : '$itemUrl/';

    final itemElement = XmlElement(XmlName('item'), [], [
      _createElement('title', item.title),
      _createElement('link', itemLink),
      _createElement('description', item.blurb),
      if (item.date != null)
        _createElement('pubDate', _formatDate(item.date!.toUtc())),
      XmlElement(
        XmlName('guid'),
        [XmlAttribute(XmlName('isPermaLink'), 'true')],
        [XmlText(itemLink)],
      ),
      // Full HTML content
      if (item.renderedContent != null && item.renderedContent!.isNotEmpty)
        XmlElement(
          XmlName('content:encoded'),
          [],
          [XmlText(item.renderedContent!)],
        )
      else
        // Fallback to blurb if no rendered content
        XmlElement(
          XmlName('content:encoded'),
          [],
          [XmlText(item.blurb)],
        ),
    ]);

    // Add categories from metadata if available
    final keywords =
        item.metadata['keywords'] ?? item.metadata['category'] ?? item.metadata['tag'];
    if (keywords != null && keywords.isNotEmpty) {
      for (final keyword in keywords.split(',')) {
        final trimmed = keyword.trim();
        if (trimmed.isNotEmpty) {
          itemElement.children.add(_createElement('category', trimmed));
        }
      }
    }

    return itemElement;
  }

  /// Helper to create a simple element with text content
  static XmlElement _createElement(String name, String text) {
    return XmlElement(XmlName(name), [], [XmlText(text)]);
  }

  /// Format DateTime to RFC 822 string for RSS
  static String _formatDate(DateTime date) {
    return DateFormat(_rfc822Format).format(date.toUtc());
  }
}
