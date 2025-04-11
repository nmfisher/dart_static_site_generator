// lib/src/fallback_root.dart
import 'dart:async';
import 'package:liquify/liquify.dart';

/// A Liquify Root implementation that tries a primary [Root] first,
/// and falls back to a secondary [Root] if the template resolution fails
/// in the primary one.
///
/// According to liquify 1.0.1's Root interface, resolve methods must throw
/// an exception if the template cannot be found, rather than returning null.
class FallbackRoot implements Root {
  final Root primaryRoot;
  final Root fallbackRoot;
  final bool logFallbacks;

  FallbackRoot(this.primaryRoot, this.fallbackRoot, {this.logFallbacks = true});

  @override
  Future<Source> resolveAsync(String path) async {
    final Source source = await primaryRoot.resolveAsync(path);
    if (!source.content.isEmpty) {
      return source;
    }

    if (logFallbacks) {
      print(
          "  -> Primary lookup failed for '$path'. Trying bundled default...");
    }

    final Source fallbackSource = await fallbackRoot.resolveAsync(path);
    if (fallbackSource.content.trim().isEmpty) {
      throw Exception(
          "Warning: Resolved template '$path' from fallback, but content is empty.");
    }

    if (logFallbacks) {
      print("  -> Using bundled default template for: $path");
    }
    return fallbackSource;
  }

  @override
  Source resolve(String path) {
    final Source source = primaryRoot.resolve(path);
    if (!source.content.isEmpty) {
      return source;
    }

    if (logFallbacks) {
      print(
          "  -> Primary lookup failed for '$path'. Trying bundled default...");
    }

    final Source fallbackSource = fallbackRoot.resolve(path);
    if (fallbackSource.content.trim().isEmpty) {
      throw Exception(
          "Warning: Resolved template '$path' from fallback, but content is empty.");
    }

    if (logFallbacks) {
      print("  -> Using bundled default template for: $path");
    }
    return fallbackSource;
  }

  @override
  Root? get parent => null;
}
