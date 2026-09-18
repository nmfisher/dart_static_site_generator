// lib/src/i18n.dart
//
// Per-locale build support (ticket 001).
//
// A site opts in by declaring a `locales:` map in config.yaml:
//
//   default_locale: en
//   locales:
//     en: { name: English }
//     de: { name: Deutsch }
//
// Every locale is then built as its own rooted site under `/<locale>/...`
// while the default locale stays at the site root. Pages written directly in
// the default locale are translated by placing a file with the same relative
// path inside `content/<locale>/`; the builder cross-links the variants with
// `alternates` (rendered as hreflang tags by the bundled seo include).

import 'config_models.dart';
import 'page_models.dart';
import 'site_urls.dart';

/// Configuration for a single locale.
class LocaleConfig {
  /// BCP 47 tag used for URLs, `<html lang>`, hreflang and RSS/xml:lang.
  final String code;

  /// Human readable name exposed to templates (`locale.name`).
  final String name;

  const LocaleConfig({required this.code, required this.name});

  factory LocaleConfig.parse(String code, dynamic value) {
    if (value == null) return LocaleConfig(code: code, name: code);
    if (value is Map) {
      return LocaleConfig(code: code, name: value['name']?.toString() ?? code);
    }
    return LocaleConfig(code: code, name: value.toString());
  }

  Map<String, dynamic> toMap() => {'code': code, 'name': name};

  @override
  bool operator ==(Object other) => other is LocaleConfig && other.code == code;

  @override
  int get hashCode => code.hashCode;
}

/// The resolved i18n configuration for a site.
class I18nConfig {
  /// All configured locales, default locale first.
  final List<LocaleConfig> locales;

  /// The locale served from the site root (no URL prefix).
  final LocaleConfig defaultLocale;

  I18nConfig({required this.locales, required this.defaultLocale})
      : assert(locales.isNotEmpty),
        assert(locales.first == defaultLocale);

  /// True when more than one locale is configured.
  bool get enabled => locales.length > 1;

  /// Parses the `default_locale` / `locales` keys of config.yaml.
  /// Returns a disabled (single default-locale) config when absent.
  factory I18nConfig.parse({dynamic locales, dynamic defaultLocale}) {
    final codes = <String>[];
    if (locales is Map) {
      for (final key in locales.keys) {
        codes.add(key.toString());
      }
    } else if (locales is List) {
      for (final entry in locales) {
        codes.add(entry.toString());
      }
    } else if (locales != null) {
      throw FormatException('locales must be a map of code -> {name}');
    }
    final defaultCode =
        defaultLocale?.toString() ?? (codes.isNotEmpty ? codes.first : 'en');
    if (codes.isEmpty) codes.add(defaultCode);
    if (!codes.contains(defaultCode)) {
      throw FormatException(
          'default_locale "$defaultCode" is not present in locales');
    }
    // Default locale first; keep the rest in declared order.
    final ordered = [defaultCode, ...codes.where((c) => c != defaultCode)];
    final parsed = <LocaleConfig>[];
    for (final code in ordered) {
      if (!RegExp(r'^[a-zA-Z0-9]+(-[a-zA-Z0-9]+)*$').hasMatch(code)) {
        throw FormatException('Invalid locale code: $code');
      }
      final value = locales is Map ? locales[code] : null;
      parsed.add(LocaleConfig.parse(code, value));
    }
    return I18nConfig(locales: parsed, defaultLocale: parsed.first);
  }

  /// The locale a content path belongs to, given the leading segment.
  /// Returns null when the first segment is not a configured locale.
  LocaleConfig? localeForSegments(List<String> segments) {
    if (segments.isEmpty) return null;
    final first = segments.first.toLowerCase();
    for (final locale in locales) {
      if (locale.code.toLowerCase() == first) return locale;
    }
    return null;
  }

  /// URL prefix for a locale; empty for the default locale.
  String prefix(LocaleConfig locale) =>
      locale == defaultLocale ? '' : '/${locale.code}';

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'default': defaultLocale.toMap(),
        'all': locales.map((l) => l.toMap()).toList(),
      };
}

/// The language-alternates of one logical page, keyed by locale code.
/// Stored in `page.extras['alternates']` by the builder.

/// Renders `<link rel="alternate" hreflang="...">` lines for a page's
/// `alternates` map (route per locale). Returns '' when the page has none.
/// An `x-default` entry pointing at the default-locale variant is emitted
/// automatically when that variant exists.
String alternateLinks(PageModel page, ConfigModel config) {
  final alternates = page.extras['alternates'];
  if (alternates is! Map || alternates.isEmpty) return '';
  final urls = SiteUrls(config);
  final buffer = StringBuffer();
  void write(String hreflang, String route) {
    buffer.write(
        '<link rel="alternate" hreflang="${_escape(hreflang)}" href="${_escape(urls.absolute(route))}">\n');
  }

  alternates.forEach((key, value) => write(key.toString(), value.toString()));
  final defaultCode = config.i18n.defaultLocale.code;
  if (alternates.containsKey(defaultCode)) {
    write('x-default', alternates[defaultCode].toString());
  }
  return buffer.toString();
}

String _escape(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
