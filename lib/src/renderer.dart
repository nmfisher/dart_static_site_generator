// lib/src/renderer.dart
import 'dart:async';
import 'package:liquify/liquify.dart';
import 'package:blog_builder/blog_builder.dart'; // Assuming ConfigModel is here
import 'package:blog_builder/src/config_models.dart'; // Ensure ConfigModel is accessible

class TemplateRenderer {
  final Root templateRoot;

  TemplateRenderer(this.templateRoot);

  /// Resolves a layout template path
  String resolveLayoutPath(String? layoutId, bool isIndex) {
    final layoutName = layoutId ?? (isIndex ? 'list' : 'default');
    return '_layouts/$layoutName.liquid'.replaceAll(r'\', '/');
  }

  /// Renders a page using the specified layout
  Future<String> renderPage(PageModel page, {String? layoutName}) async {
    final layoutPath =
        resolveLayoutPath(layoutName ?? page.layoutId, page.isIndex);

    final Map<String, dynamic> renderData = {
      'page': page.toMap(),
      'content': page.html,
    };

    return await _renderWithTemplate(layoutPath, renderData);
  }

  /// Renders a page with site configuration data included
  Future<String> renderPageWithSiteConfig(
      PageModel page, ConfigModel siteConfig,
      {String? layoutName}) async {
    final layoutPath =
        resolveLayoutPath(layoutName ?? page.layoutId, page.isIndex);

    final Map<String, dynamic> renderData = {
      'site': siteConfig.toMap(),
      'page': page.toMap(),
      'content': page.html,
    };

    return await _renderWithTemplate(layoutPath, renderData);
  }

  Future<String> _renderWithTemplate(
      String layoutPath, Map<String, dynamic> renderData) async {
    try {
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
    } catch (e, s) {
      // Capture stack trace for better debugging
      print("Error rendering template '$layoutPath'. Exception: $e");
      print("Stack trace:\n$s");
      // Re-throw the wrapped exception to keep test expectations consistent for now
      throw Exception("Error rendering template '$layoutPath': $e");
    }
  }
}
