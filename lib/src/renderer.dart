import 'dart:async';
import 'package:liquify/liquify.dart';
import 'package:intl/intl.dart'; // Import for date formatting
import 'dart:math'; // New import for min function
import 'package:markdown/markdown.dart' as md; // New import for markdownToHtml
import 'package:blog_builder/blog_builder.dart';
import 'package:blog_builder/src/site_data_model.dart'; // New import

class TemplateRenderer {
  final Root templateRoot;

  TemplateRenderer(this.templateRoot);

  String resolveLayoutPath(String? layoutId, bool isIndex) {
    final layoutName = layoutId ?? (isIndex ? 'list' : 'default');
    return '_layouts/$layoutName.liquid'.replaceAll(r'\', '/');
  }

  // Prepares the data map used for rendering
  Map<String, dynamic> _prepareRenderData(PageModel page, ConfigModel siteConfig, SiteData siteData) {
    final Map<String, dynamic> renderData = {
      'site': siteConfig.toMap(),
      'page': page.toMap(),
    };
    (renderData['site'] as Map<String, dynamic>).addAll(siteData.toLiquidMap());

    if (page.date != null) {
      (renderData['page'] as Map<String, dynamic>)['formatted_date'] =
          _formatDate(page.date!, "%Y-%m-%d");
    }
    return renderData;
  }

  /// Pass 1: Renders the page's markdown content to HTML.
  Future<String> renderContent(PageModel page, ConfigModel siteConfig, SiteData siteData) async {
    final renderData = _prepareRenderData(page, siteConfig, siteData);
    String processedMarkdown = page.rawMarkdown;
    
    if (page.rawMarkdown.isNotEmpty) {
      try {
        final markdownTemplate = Template.parse(
          processedMarkdown,
          data: renderData,
          root: templateRoot,
        );
        processedMarkdown = await markdownTemplate.render();
      } catch (e, s) {
        print("Error processing Liquid in markdown for page ${page.route}. Exception: $e");
        print("Stack trace:\n$s");
        rethrow;
      }
    }
    
    return md.markdownToHtml(
      processedMarkdown,
      extensionSet: md.ExtensionSet.gitHubFlavored,
    );
  }

  /// Pass 2: Renders the final page with its layout.
  Future<String> renderPageWithLayout(
      PageModel page, ConfigModel siteConfig, SiteData siteData,
      {String? layoutName}) async {
    final layoutPath =
        resolveLayoutPath(layoutName ?? page.layoutId, page.isIndex);
    print("Resolved layoutPath : $layoutPath");

    final renderData = _prepareRenderData(page, siteConfig, siteData);
    
    // Use the pre-rendered content from pass 1
    renderData['content'] = page.renderedContent ?? '';

    final layoutSource = await templateRoot.resolveAsync(layoutPath);

    if (layoutSource.content.trim().isEmpty) {
      throw Exception("Layout template is empty: $layoutPath");
    }

    final template = Template.parse(
      layoutSource.content,
      data: renderData,
      root: templateRoot,
    );

    final renderedContent = await template.render();

    if (renderedContent.trim().isEmpty) {
      throw Exception("Rendered content is empty");
    }

    return renderedContent;
  }

  String _formatDate(DateTime date, String formatString) {
    String dartFormat = formatString
        .replaceAll('%Y', 'yyyy')
        .replaceAll('%y', 'yy')
        .replaceAll('%m', 'MM')
        .replaceAll('%d', 'dd')
        .replaceAll('%H', 'HH')
        .replaceAll('%I', 'hh')
        .replaceAll('%M', 'mm')
        .replaceAll('%S', 'ss')
        .replaceAll('%a', 'EEE')
        .replaceAll('%A', 'EEEE')
        .replaceAll('%b', 'MMM')
        .replaceAll('%B', 'MMMM')
        .replaceAll('%j', 'DDD') // Day of year (approximate)
        .replaceAll('%w', 'w')   // Weekday (approximate)
        .replaceAll('%U', 'ww')  // Week number (approximate)
        .replaceAll('%W', 'ww')  // Week number (approximate)
        .replaceAll('%c', 'EEE MMM dd HH:mm:ss yyyy')
        .replaceAll('%x', 'MM/dd/yy')
        .replaceAll('%X', 'HH:mm:ss')
        .replaceAll('%Z', 'zzz')
        .replaceAll('%z', 'Z')
        .replaceAll('%%', '%');

    try {
      return DateFormat(dartFormat).format(date);
    } catch (e) {
      return date.toIso8601String(); // Fallback
    }
  }
}