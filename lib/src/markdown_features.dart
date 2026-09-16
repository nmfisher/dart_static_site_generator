import 'package:highlight/highlight.dart' show highlight;
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'config_models.dart';
import 'page_models.dart';

String slugify(String text) => text
    .toLowerCase()
    .trim()
    .replaceAll(RegExp(r'[^\p{L}\p{N}\s_-]', unicode: true), '')
    .replaceAll(RegExp(r'[\s_]+'), '-')
    .replaceAll(RegExp(r'-+'), '-');

String enhanceMarkdown(String source, PageModel page, ConfigModel config) {
  final fragment = html.parseFragment(source);
  var changed = false;
  page.headings = [];
  page.tableOfContents = '';
  if (config.headingAnchors || config.tableOfContents) {
    final used = fragment.querySelectorAll('[id]').map((e) => e.id).toSet();
    for (final heading in fragment.querySelectorAll('h1,h2,h3,h4,h5,h6')) {
      final title = heading.text;
      var id = heading.id;
      if (id.isEmpty) {
        final slug = slugify(title);
        final base = slug.isEmpty ? 'section' : slug;
        id = base;
        var index = 2;
        while (used.contains(id)) {
          id = '$base-${index++}';
        }
        heading.id = id;
      }
      used.add(id);
      page.headings.add({
        'id': id,
        'title': title,
        'level': int.parse(heading.localName!.substring(1))
      });
      if (config.headingAnchors) {
        final anchor = dom.Element.tag('a')
          ..attributes['class'] = 'heading-anchor'
          ..attributes['href'] = '#${Uri.encodeComponent(id)}'
          ..attributes['aria-label'] = 'Link to $title'
          ..text = '#';
        heading.nodes.add(anchor);
      }
      changed = true;
    }
    if (config.tableOfContents && page.headings.isNotEmpty) {
      final nav = dom.Element.tag('nav')
        ..classes.add('table-of-contents')
        ..attributes['aria-label'] = 'Table of contents';
      nav.nodes.add(dom.Element.tag('h2')..text = 'On this page');
      final list = dom.Element.tag('ol');
      for (final heading in page.headings) {
        final item = dom.Element.tag('li')
          ..classes.add('toc-level-${heading['level']}');
        item.nodes.add(dom.Element.tag('a')
          ..attributes['href'] = '#${Uri.encodeComponent(heading['id'])}'
          ..text = heading['title']);
        list.nodes.add(item);
      }
      nav.nodes.add(list);
      page.tableOfContents = nav.outerHtml;
    }
  }
  if (config.highlighting) {
    for (final code in fragment.querySelectorAll('pre > code')) {
      final languages = code.classes.where((c) => c.startsWith('language-'));
      if (languages.isEmpty) continue;
      final language = languages.first.substring(9);
      if (language.isEmpty || language == 'text' || language == 'plaintext')
        continue;
      try {
        final result = highlight.parse(code.text, language: language).toHtml();
        code.nodes
          ..clear()
          ..addAll(html.parseFragment(result).nodes.toList());
        code.classes.add('hljs');
        changed = true;
      } catch (_) {
        // Unknown languages remain readable, escaped code blocks.
      }
    }
  }
  return changed ? fragment.outerHtml : source;
}

String plainContent(String htmlSource) {
  final fragment = html.parseFragment(htmlSource);
  for (final element
      in fragment.querySelectorAll('script,style,.heading-anchor')) {
    element.remove();
  }
  return fragment.text?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
}
