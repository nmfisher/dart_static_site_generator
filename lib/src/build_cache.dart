import 'dart:collection';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:file/file.dart';
import 'package:liquify/liquify.dart';

String fingerprint(Object? value) => sha256
    .convert(utf8.encode(jsonEncode(value,
        toEncodable: (v) =>
            v is DateTime ? v.toIso8601String() : v.toString())))
    .toString();
String bytesFingerprint(List<int> value) => sha256.convert(value).toString();

class BuildCache {
  final FileSystem fs;
  final String directory;
  final bool enabled;
  int parsedHits = 0, contentHits = 0, layoutHits = 0, assetHits = 0;
  BuildCache(this.fs, this.directory, {this.enabled = true});
  void resetStats() {
    parsedHits = contentHits = layoutHits = assetHits = 0;
  }

  Map<String, dynamic>? read(String kind, String key) {
    if (!enabled) return null;
    try {
      final value = Map<String, dynamic>.from(jsonDecode(fs
          .file(fs.path.join(directory, 'v1', kind, '$key.json'))
          .readAsStringSync()));
      if (kind == 'content' || kind == 'layout') {
        if (value['html'] is! String ||
            value['templates'] is! Map ||
            value['site_reads'] is! Map ||
            value['headings'] is! List) return null;
        for (final key in (value['site_reads'] as Map).keys) {
          if (jsonDecode(key) is! List) return null;
        }
      } else if (kind == 'pages') {
        if (value['source'] is! String ||
            value['rawMarkdown'] is! String ||
            value['route'] is! String ||
            value['metadata'] is! Map ||
            value['extras'] is! Map) return null;
        if (value['date'] != null && DateTime.tryParse(value['date']) == null)
          return null;
      }
      return value;
    } catch (_) {
      return null;
    }
  }

  void write(String kind, String key, Map<String, dynamic> value) {
    if (!enabled) return;
    final file = fs.file(fs.path.join(directory, 'v1', kind, '$key.json'));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(jsonEncode(value));
  }

  String artifact(String key, String name) =>
      fs.path.join(directory, 'v1', 'assets', key, name);
}

class TrackingRoot implements Root {
  final Root delegate;
  final Map<String, String> dependencies = {};
  bool volatile = false;
  TrackingRoot(this.delegate);
  Source record(String path, Source source) {
    dependencies[path] = fingerprint(source.content);
    volatile |= RegExp(r'''['"](?:now|today)['"]''').hasMatch(source.content);
    return Source(source.file, source.content, this);
  }

  @override
  Source resolve(String path) => record(path, delegate.resolve(path));
  @override
  Future<Source> resolveAsync(String path) async =>
      record(path, await delegate.resolveAsync(path));
}

// Track individual site values. Lists and map enumeration are treated as whole
// dependencies, so collection membership and ordering cannot become stale.
class SiteReads {
  final Map<String, dynamic> source;
  final Map<String, String> reads = {};
  SiteReads(this.source);
  Map<String, dynamic> get tracked => _TrackedMap(source, [], this);
  void record(List<String> path, Object? value, {bool shape = false}) {
    reads[jsonEncode([shape, ...path])] = fingerprint(value);
  }

  static bool matches(Map<String, dynamic> source, Map reads) {
    for (final entry in reads.entries) {
      final parts = jsonDecode(entry.key as String) as List;
      dynamic value = source;
      for (final part in parts.skip(1)) {
        value = value is Map ? value[part] : null;
      }
      if (parts.first == true)
        value = value is Map ? value.keys.toList() : null;
      if (fingerprint(value) != entry.value) return false;
    }
    return true;
  }
}

class _TrackedMap extends MapBase<String, dynamic> {
  final Map<String, dynamic> source;
  final List<String> path;
  final SiteReads tracker;
  _TrackedMap(this.source, this.path, this.tracker);
  @override
  dynamic operator [](Object? key) {
    final value = source[key];
    final child = [...path, key.toString()];
    if (value is Map<String, dynamic>) {
      tracker.record(child, value.keys.toList(), shape: true);
      return _TrackedMap(value, child, tracker);
    }
    tracker.record(child, value);
    return value;
  }

  @override
  Iterable<String> get keys {
    tracker.record(path, source.keys.toList(), shape: true);
    return source.keys;
  }

  @override
  void operator []=(String key, dynamic value) {
    source[key] = value;
  }

  @override
  void clear() => source.clear();
  @override
  dynamic remove(Object? key) => source.remove(key);
}
