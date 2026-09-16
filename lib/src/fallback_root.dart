// lib/src/fallback_root.dart
import 'dart:async';
import 'package:liquify/liquify.dart';

/// A Liquify Root implementation that tries a primary [Root] first,
/// and falls back to a secondary [Root] if the template resolution fails
/// in the primary one. Both roots must use `throwOnMissing: true` so that
/// an intentionally empty partial remains a valid override.
class FallbackRoot implements Root {
  final Root primaryRoot;
  final Root fallbackRoot;
  final bool logFallbacks;

  FallbackRoot(this.primaryRoot, this.fallbackRoot, {this.logFallbacks = true});

  @override
  Future<Source> resolveAsync(String path) async {
    try {
      final Source source = await primaryRoot.resolveAsync(path);
      return source;
    } on TemplateNotFoundException {
      // Primary failed to resolve, try fallback
      if (logFallbacks) {
        print(
            "  -> Primary lookup failed for '$path'. Trying bundled default...");
      }

      final Source fallbackSource = await fallbackRoot.resolveAsync(path);

      if (logFallbacks) {
        print("  -> Using bundled default template for: $path");
      }
      return fallbackSource;
    }
  }

  @override
  Source resolve(String path) {
    try {
      final Source source = primaryRoot.resolve(path);
      return source;
    } on TemplateNotFoundException {
      // Primary failed to resolve, try fallback
      if (logFallbacks) {
        print(
            "  -> Primary lookup failed for '$path'. Trying bundled default...");
      }

      final Source fallbackSource = fallbackRoot.resolve(path);

      if (logFallbacks) {
        print("  -> Using bundled default template for: $path");
      }
      return fallbackSource;
    }
  }
}
