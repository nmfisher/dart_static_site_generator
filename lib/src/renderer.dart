import 'dart:async';
import 'package:liquify/liquify.dart';
import 'package:blog_builder/blog_builder.dart';

class TemplateRenderer {
  final Root templateRoot;

  TemplateRenderer(this.templateRoot);

  String resolveLayoutPath(String? layoutId, bool isIndex) {
    final layoutName = layoutId ?? (isIndex ? 'list' : 'default');
    return '_layouts/$layoutName.liquid'.replaceAll(r'\', '/');
  }

  Future<String> renderPage(PageModel page, {String? layoutName}) async {
    final layoutPath =
        resolveLayoutPath(layoutName ?? page.layoutId, page.isIndex);

    final Map<String, dynamic> renderData = {
      'page': page.toMap(),
      'content': page.html,
    };

    return await _renderWithTemplate(layoutPath, renderData);
  }

  Future<String> renderPageWithSiteConfig(
      PageModel page, ConfigModel siteConfig,
      {String? layoutName}) async {
    final layoutPath =
        resolveLayoutPath(layoutName ?? page.layoutId, page.isIndex);
    print("Resolved layoutPath : $layoutPath");
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
      print("Error rendering template '$layoutPath'. Exception: $e");
      print("Stack trace:\n$s");
      rethrow;
    }
  }
}
