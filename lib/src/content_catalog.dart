import 'dart:math';
import 'package:path/path.dart' as p;
import 'config_models.dart';
import 'i18n.dart';
import 'page_models.dart';
import 'markdown_features.dart';

class ContentCatalog {
  final Map<String, List<PageModel>> collections = {},
      tags = {},
      categories = {};
  final ConfigModel config;
  final I18nConfig i18n;
  ContentCatalog(this.config, {I18nConfig? i18n})
      : i18n = i18n ?? config.i18n;

  void collect(List<PageModel> pages, String contentDir) {
    for (final entry in config.collections.entries) {
      collections[entry.key] = [];
    }
    for (final page in pages.where((p) => !p.isIndex && !p.generated)) {
      final source = p
          .relative(page.source, from: contentDir)
          .replaceAll(p.separator, '/');
      final matches = config.collections.values
          .where((c) => source.startsWith('${c.path}/'))
          .toList()
        ..sort((a, b) => b.path.length.compareTo(a.path.length));
      final name = page.extras['collection']?.toString() ??
          (matches.isNotEmpty
              ? matches.first.name
              : (source.contains('/') ? source.split('/').first : 'pages'));
      if (page.locale != null) {
        // Translated pages only join per-locale buckets (`<name>@<locale>`),
        // paginated under /<locale>/... by archives().
        collections
            .putIfAbsent('$name@${page.locale}', () => [])
            .add(page);
        continue;
      }
      collections.putIfAbsent(name, () => []).add(page);
      for (final target in [
        MapEntry('tags', tags),
        MapEntry('categories', categories)
      ]) {
        final raw = page.extras[target.key];
        final values =
            raw is List ? raw : (raw == null ? [] : raw.toString().split(','));
        for (final term in values
            .map((v) => v.toString().trim())
            .where((v) => v.isNotEmpty)
            .toSet()) {
          target.value.putIfAbsent(term, () => []).add(page);
        }
      }
    }
    for (final items in [
      ...collections.values,
      ...tags.values,
      ...categories.values
    ]) {
      items.sort(comparePages);
    }
  }

  static int comparePages(PageModel a, PageModel b) {
    final ap = int.tryParse('${a.extras['priority']}');
    final bp = int.tryParse('${b.extras['priority']}');
    if (ap != null || bp != null) {
      final cmp = (ap ?? 2147483647).compareTo(bp ?? 2147483647);
      if (cmp != 0) return cmp;
    }
    final cmp = (b.date ?? DateTime(0)).compareTo(a.date ?? DateTime(0));
    return cmp != 0 ? cmp : a.route.compareTo(b.route);
  }

  List<PageModel> archives(List<PageModel> existing) {
    final generated = <PageModel>[];
    void paginate(String route, String title, List<PageModel> items, int size,
        {bool allowManual = false}) {
      final total = max(1, (items.length / size).ceil());
      for (var number = 1; number <= total; number++) {
        final pageRoute = number == 1 ? route : '$route/page/$number';
        final pagination = {
          'page': number,
          'total_pages': total,
          'total_items': items.length,
          'page_size': size,
          'previous': number <= 1
              ? null
              : (number == 2 ? route : '$route/page/${number - 1}'),
          'next': number == total ? null : '$route/page/${number + 1}',
          'pages': List.generate(
              total,
              (i) => {
                    'number': i + 1,
                    'route': i == 0 ? route : '$route/page/${i + 1}'
                  })
        };
        final slice = items.skip((number - 1) * size).take(size).toList();
        final manual = existing.where((p) => p.route == pageRoute).toList();
        if (allowManual &&
            manual.isNotEmpty &&
            manual.first.isIndex &&
            number == 1) {
          final index = existing.indexOf(manual.first);
          existing[index] = PageIndexPageModel(
              title: manual.first.title,
              route: pageRoute,
              source: manual.first.source,
              rawMarkdown: manual.first.rawMarkdown,
              layoutId: manual.first.layoutId,
              metadata: manual.first.metadata,
              blurb: manual.first.blurb,
              children: slice,
              extras: {...manual.first.extras, 'pagination': pagination});
          continue;
        }
        generated.add(PageIndexPageModel(
            title: title,
            route: pageRoute,
            source: 'generated:$pageRoute',
            layoutId: 'list',
            metadata: {},
            blurb: '',
            children: slice,
            extras: {'pagination': pagination}));
      }
    }

    for (final entry in config.collections.entries) {
      paginate('/${entry.value.path}', entry.value.title,
          collections[entry.key] ?? [], entry.value.pageSize,
          allowManual: true);
      // Per-locale archives (ticket 001): paginate the translated pages
      // of each non-default locale under /<locale>/<collection path>/...
      for (final locale in i18n.locales.skip(1)) {
        final translated =
            collections['${entry.key}@${locale.code}'] ?? const <PageModel>[];
        if (translated.isEmpty) continue;
        paginate('${i18n.prefix(locale)}/${entry.value.path}',
            entry.value.title, translated, entry.value.pageSize);
      }
    }
    for (final target in [
      MapEntry('tags', tags),
      MapEntry('categories', categories)
    ]) {
      final slugs = <String, String>{};
      for (final entry in target.value.entries) {
        final slug = slugify(entry.key);
        if (slug.isEmpty ||
            (slugs.containsKey(slug) && slugs[slug] != entry.key))
          throw FormatException(
              'Conflicting ${target.key} slug for "${entry.key}"');
        slugs[slug] = entry.key;
        paginate(
            '/${target.key}/$slug', entry.key, entry.value, config.pageSize);
      }
    }
    return generated;
  }

  void addNavigation(List<PageModel> pages) {
    final navigation = <String, Map<String, dynamic>>{};
    Map<String, dynamic> summary(PageModel p) =>
        {'title': p.title, 'route': p.route};
    for (final items in collections.values) {
      for (var i = 0; i < items.length; i++) {
        navigation[items[i].source] = {
          'previous': i == 0 ? null : summary(items[i - 1]),
          'next': i + 1 == items.length ? null : summary(items[i + 1])
        };
      }
    }
    for (var i = 0; i < pages.length; i++) {
      final nav = navigation[pages[i].source];
      if (nav != null)
        pages[i] = pages[i].copyWith(extras: {...pages[i].extras, ...nav});
    }
    rebind(pages);
  }

  void rebind(List<PageModel> pages) {
    final bySource = {for (final page in pages) page.source: page};
    for (final page in pages.whereType<PageIndexPageModel>()) {
      for (var i = 0; i < page.children.length; i++) {
        page.children[i] =
            bySource[page.children[i].source] ?? page.children[i];
      }
    }
    for (final list in [
      ...collections.values,
      ...tags.values,
      ...categories.values
    ]) {
      for (var i = 0; i < list.length; i++) {
        list[i] = bySource[list[i].source]!;
      }
    }
  }

  Map<String, dynamic> toMap() => {
        'collections': {
          for (final entry in collections.entries)
            if (!entry.key.contains('@'))
              entry.key: {
              'name': entry.key,
              'title': config.collections[entry.key]?.title ?? entry.key,
              'route': '/${config.collections[entry.key]?.path ?? entry.key}',
              'all': entry.value.map((p) => p.toMap()).toList(),
                'count': entry.value.length
              }
        },
        'tags': {
          for (final entry in tags.entries)
            entry.key: entry.value.map((p) => p.toMap()).toList()
        },
        'categories': {
          for (final entry in categories.entries)
            entry.key: entry.value.map((p) => p.toMap()).toList()
        },
      };
}
