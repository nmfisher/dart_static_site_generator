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
    // 1. Try primary root
    try {
      final Source source = await primaryRoot.resolveAsync(path);
      // If primaryRoot.resolveAsync completes without throwing, we found it.
      return source;
    } catch (primaryError) {
      // Primary root failed (e.g., threw FileNotFoundException or similar).
      // Now try the fallback root.
      if (logFallbacks) {
          // Log the attempt *before* potentially succeeding or failing with fallback
          print("  -> Primary lookup failed for '$path'. Trying bundled default...");
      }
      try {
        final Source fallbackSource = await fallbackRoot.resolveAsync(path);
        // If fallbackRoot.resolveAsync completes without throwing, we found it.
        if (logFallbacks) {
             print("  -> Using bundled default template for: $path");
        }
        return fallbackSource;
      } catch (fallbackError) {
        // Fallback also failed. Re-throw a specific error or the original primary error.
        // Throwing a new error provides more context.
         throw Exception(
              "Template '$path' not found in user templates (error: $primaryError) or bundled defaults (error: $fallbackError).");
        // Alternatively, re-throw the primary error if you prefer:
        // throw primaryError;
      }
    }
  }

  @override
  Source resolve(String path) {
    // Sync version - follows the same logic as resolveAsync
    // 1. Try primary root
    try {
      final Source source = primaryRoot.resolve(path);
      // If primaryRoot.resolve completes without throwing, we found it.
      return source;
    } catch (primaryError) {
       // Primary root failed. Try the fallback root.
       if (logFallbacks) {
           print("  -> Primary sync lookup failed for '$path'. Trying bundled default...");
       }
      try {
        final Source fallbackSource = fallbackRoot.resolve(path);
         // If fallbackRoot.resolve completes without throwing, we found it.
         if (logFallbacks) {
             print("  -> Using bundled default sync template for: $path");
         }
        return fallbackSource;
      } catch (fallbackError) {
         // Fallback also failed.
         throw Exception(
              "Template '$path' not found synchronously in user templates (error: $primaryError) or bundled defaults (error: $fallbackError).");
        // throw primaryError;
      }
    }
  }

  @override
  Root? get parent => null; // Fallback doesn't naturally have a single parent

  // No list() method as it's not defined in liquify 1.0.1 Root interface.
  // Add other methods like `cache`, `loader` if the Root interface evolves
  // or if liquify requires them, potentially delegating to the primary root.
}