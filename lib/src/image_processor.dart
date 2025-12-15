// lib/src/image_processor.dart
import 'dart:typed_data';
import 'dart:io';
import 'package:file/file.dart';
import 'package:path/path.dart' as path;
import 'package:image/image.dart' as img;

/// Configuration for image optimization settings
class ImageOptimizationConfig {
  final bool enabled;
  final PngConfig png;
  final JpegConfig jpeg;
  final WebPConfig webp;

  ImageOptimizationConfig({
    this.enabled = false,
    PngConfig? png,
    JpegConfig? jpeg,
    WebPConfig? webp,
  })  : png = png ?? PngConfig(),
        jpeg = jpeg ?? JpegConfig(),
        webp = webp ?? WebPConfig();

  factory ImageOptimizationConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return ImageOptimizationConfig();
    }

    return ImageOptimizationConfig(
      enabled: map['enabled'] as bool? ?? false,
      png: PngConfig.fromMap(map['png'] as Map<String, dynamic>?),
      jpeg: JpegConfig.fromMap(map['jpeg'] as Map<String, dynamic>?),
      webp: WebPConfig.fromMap(map['webp'] as Map<String, dynamic>?),
    );
  }
}

/// PNG-specific compression settings
class PngConfig {
  final bool enabled;
  final int level; // 0-9, higher = more compression
  final bool stripMetadata;

  PngConfig({
    this.enabled = true,
    this.level = 6,
    this.stripMetadata = true,
  });

  factory PngConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return PngConfig();
    }

    return PngConfig(
      enabled: map['enabled'] as bool? ?? true,
      level: (map['compression_level'] as int?) ?? 6,
      stripMetadata: map['strip_metadata'] as bool? ?? true,
    );
  }
}

/// JPEG-specific compression settings (placeholder for Phase 2)
class JpegConfig {
  final bool enabled;
  final int quality; // 0-100

  JpegConfig({
    this.enabled = true,
    this.quality = 85,
  });

  factory JpegConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return JpegConfig();
    }

    return JpegConfig(
      enabled: map['enabled'] as bool? ?? true,
      quality: (map['quality'] as int?) ?? 85,
    );
  }
}

/// WebP-specific compression settings
class WebPConfig {
  final bool enabled;
  final int quality; // 0-100
  final int method; // 0-6, compression method/speed tradeoff
  final bool createFallbacks; // Keep original format alongside WebP

  WebPConfig({
    this.enabled = false, // Disabled by default as it's a conversion
    this.quality = 80,
    this.method = 4,
    this.createFallbacks = true,
  });

  factory WebPConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return WebPConfig();
    }

    return WebPConfig(
      enabled: map['enabled'] as bool? ?? false,
      quality: (map['quality'] as int?) ?? 80,
      method: (map['method'] as int?) ?? 4,
      createFallbacks: map['create_fallbacks'] as bool? ?? true,
    );
  }
}

/// Result of processing a single image
class ImageProcessResult {
  final String inputPath;
  final String outputPath;
  final int originalSize;
  final int compressedSize;
  final bool success;
  final String? error;

  ImageProcessResult({
    required this.inputPath,
    required this.outputPath,
    required this.originalSize,
    required this.compressedSize,
    required this.success,
    this.error,
  });

  int get savings => originalSize - compressedSize;
  double get savingsPercent =>
      originalSize > 0 ? (savings / originalSize) * 100 : 0;
}

/// Statistics for all processed images
class ImageProcessingStats {
  int totalImages = 0;
  int processedImages = 0;
  int skippedImages = 0;
  int totalOriginalSize = 0;
  int totalCompressedSize = 0;
  final List<ImageProcessResult> results = [];

  int get totalSavings => totalOriginalSize - totalCompressedSize;
  double get savingsPercent =>
      totalOriginalSize > 0 ? (totalSavings / totalOriginalSize) * 100 : 0;

  void addResult(ImageProcessResult result) {
    results.add(result);
    totalImages++;
    processedImages++;
    totalOriginalSize += result.originalSize;
    totalCompressedSize += result.compressedSize;
  }

  void printSummary() {
    print('\n--- Image Processing Summary ---');
    print('Total images processed: $processedImages/$totalImages');
    if (skippedImages > 0) {
      print('Skipped (non-image files): $skippedImages');
    }
    if (processedImages > 0) {
      print('Original size: ${formatBytes(totalOriginalSize)}');
      print('Compressed size: ${formatBytes(totalCompressedSize)}');
      print(
          'Total savings: ${formatBytes(totalSavings)} (${savingsPercent.toStringAsFixed(1)}%)');
    }
    print('--------------------------------');
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}

/// Handles image compression and optimization
class ImageProcessor {
  final ImageOptimizationConfig config;
  final ImageProcessingStats stats = ImageProcessingStats();
  final Map<String, String> webpMappings = {}; // Track WebP conversions

  static const Set<String> _pngExtensions = {'.png'};
  static const Set<String> _jpegExtensions = {'.jpg', '.jpeg'};
  static const Set<String> _webpExtensions = {'.webp'};
  static const Set<String> _supportedExtensions = {
    '.png',
    '.jpg',
    '.jpeg',
    '.webp',
    // Future: '.gif'
  };

  ImageProcessor({required this.config});

  /// Check if a file path is a supported image format
  bool isImageFile(String path) {
    final ext = path.toLowerCase();
    return _supportedExtensions.any((e) => ext.endsWith(e));
  }

  /// Check if a file is a PNG
  bool isPng(String path) {
    final ext = path.toLowerCase();
    return _pngExtensions.any((e) => ext.endsWith(e));
  }

  /// Check if a file is a JPEG
  bool isJpeg(String path) {
    final ext = path.toLowerCase();
    return _jpegExtensions.any((e) => ext.endsWith(e));
  }

  /// Check if a file is a WebP
  bool isWebp(String path) {
    final ext = path.toLowerCase();
    return _webpExtensions.any((e) => ext.endsWith(e));
  }

  /// Process a single image file
  Future<ImageProcessResult> processImage(File inputFile, File outputFile) async {
    final inputPath = inputFile.path;
    final outputPath = outputFile.path;

    final originalBytes = await inputFile.readAsBytes();
    final originalSize = originalBytes.length;

    Uint8List compressedBytes;

    if (isPng(inputPath) && config.png.enabled) {
      compressedBytes = await _compressPng(originalBytes);
    } else if (isJpeg(inputPath) && config.jpeg.enabled) {
      compressedBytes = await _compressJpeg(originalBytes);
    } else {
      // Unsupported format or disabled - copy as-is
      await inputFile.copy(outputPath);
      stats.skippedImages++;
      return ImageProcessResult(
        inputPath: inputPath,
        outputPath: outputPath,
        originalSize: originalSize,
        compressedSize: originalSize,
        success: true,
      );
    }

    // Only use compressed version if it's actually smaller
    if (compressedBytes.length < originalSize) {
      await outputFile.writeAsBytes(compressedBytes);
      final result = ImageProcessResult(
        inputPath: inputPath,
        outputPath: outputPath,
        originalSize: originalSize,
        compressedSize: compressedBytes.length,
        success: true,
      );
      stats.addResult(result);
      return result;
    } else {
      // Compressed file is larger or same size - keep original
      await inputFile.copy(outputPath);
      final result = ImageProcessResult(
        inputPath: inputPath,
        outputPath: outputPath,
        originalSize: originalSize,
        compressedSize: originalSize,
        success: true,
      );
      stats.addResult(result);
      return result;
    }
  }

  /// Process a single image file with optional WebP conversion
  Future<List<ImageProcessResult>> processImageWithWebP(File inputFile, File outputFile, {required FileSystem fileSystem, String? assetsBasePath}) async {
    final inputPath = inputFile.path;
    final outputPath = outputFile.path;
    final results = <ImageProcessResult>[];

    final originalBytes = await inputFile.readAsBytes();
    final originalSize = originalBytes.length;

    // Process the original format first
    Uint8List compressedBytes;
    bool shouldCompressOriginal = false;

    if (isPng(inputPath) && config.png.enabled) {
      compressedBytes = await _compressPng(originalBytes);
      shouldCompressOriginal = true;
    } else if (isJpeg(inputPath) && config.jpeg.enabled) {
      compressedBytes = await _compressJpeg(originalBytes);
      shouldCompressOriginal = true;
    } else {
      compressedBytes = originalBytes;
    }

    // Save original/compressed format if needed
    if (config.webp.enabled && config.webp.createFallbacks && (isPng(inputPath) || isJpeg(inputPath))) {
      // Save the original/compressed version
      if (shouldCompressOriginal && compressedBytes.length < originalSize) {
        await outputFile.writeAsBytes(compressedBytes);
        results.add(ImageProcessResult(
          inputPath: inputPath,
          outputPath: outputPath,
          originalSize: originalSize,
          compressedSize: compressedBytes.length,
          success: true,
        ));
      } else {
        await inputFile.copy(outputPath);
        results.add(ImageProcessResult(
          inputPath: inputPath,
          outputPath: outputPath,
          originalSize: originalSize,
          compressedSize: originalSize,
          success: true,
        ));
      }
    } else if (shouldCompressOriginal && compressedBytes.length < originalSize) {
      // Only WebP conversion, no fallback needed
      await outputFile.writeAsBytes(compressedBytes);
      results.add(ImageProcessResult(
        inputPath: inputPath,
        outputPath: outputPath,
        originalSize: originalSize,
        compressedSize: compressedBytes.length,
        success: true,
      ));
    } else if (!config.webp.enabled) {
      // No WebP conversion, save original
      await inputFile.copy(outputPath);
      results.add(ImageProcessResult(
        inputPath: inputPath,
        outputPath: outputPath,
        originalSize: originalSize,
        compressedSize: originalSize,
        success: true,
      ));
    }

    // Convert to WebP if enabled and input is PNG/JPEG
    if (config.webp.enabled && (isPng(inputPath) || isJpeg(inputPath))) {
      try {
        final webpBytes = await _convertToWebp(originalBytes, inputFile, fileSystem: fileSystem);
        final webpOutputPath = '${path.withoutExtension(outputPath)}.webp';
        await fileSystem.file(webpOutputPath).writeAsBytes(webpBytes);

        // Track the WebP conversion for HTML processing
        if (assetsBasePath != null) {
          final relativeOriginal = path.relative(inputPath, from: assetsBasePath);
          final relativeWebP = path.relative(webpOutputPath, from: assetsBasePath);
          // Store paths relative to the base path (usually the build directory)
          webpMappings[path.join('assets', path.basename(relativeOriginal))] =
              path.join('assets', path.basename(relativeWebP));
        }

        final webpResult = ImageProcessResult(
          inputPath: inputPath,
          outputPath: webpOutputPath,
          originalSize: originalSize,
          compressedSize: webpBytes.length,
          success: true,
        );
        results.add(webpResult);
        stats.addResult(webpResult);
      } catch (e) {
        // If WebP conversion fails, add error result but don't fail the build
        results.add(ImageProcessResult(
          inputPath: inputPath,
          outputPath: outputPath,
          originalSize: originalSize,
          compressedSize: originalSize,
          success: false,
          error: 'WebP conversion failed: $e',
        ));
      }
    }

    // Update stats for all results
    for (final result in results) {
      if (result.success && !result.outputPath.endsWith('.webp')) {
        stats.addResult(result);
      }
    }

    return results;
  }

  /// Compress a PNG image
  Future<Uint8List> _compressPng(Uint8List bytes) async {
    final image = img.decodeImage(bytes);
    if (image == null) {
      throw Exception('Failed to decode PNG image');
    }

    // Use PNG encoder with compression level
    final encoder = img.PngEncoder(level: config.png.level);
    return Uint8List.fromList(encoder.encode(image));
  }

  /// Compress a JPEG image (Phase 1 basic support)
  Future<Uint8List> _compressJpeg(Uint8List bytes) async {
    final image = img.decodeImage(bytes);
    if (image == null) {
      throw Exception('Failed to decode JPEG image');
    }

    // Use JPEG encoder with quality setting
    final encoder = img.JpegEncoder(quality: config.jpeg.quality);
    return Uint8List.fromList(encoder.encode(image));
  }

  /// Convert image to WebP format using cwebp tool
  Future<Uint8List> _convertToWebp(Uint8List bytes, File inputFile, {required FileSystem fileSystem}) async {
    // Create temporary files for conversion
    final tempInput = fileSystem.file('${inputFile.path}.tmp');
    final tempOutput = fileSystem.file('${inputFile.path}.webp.tmp');

    try {
      // Write input bytes to temp file
      await tempInput.writeAsBytes(bytes);

      // Run cwebp command
      final result = await Process.run('cwebp', [
        '-q', config.webp.quality.toString(),
        '-m', config.webp.method.toString(),
        tempInput.path,
        '-o', tempOutput.path,
      ]);

      if (result.exitCode != 0) {
        throw Exception('cwebp failed: ${result.stderr}');
      }

      // Read the converted WebP bytes
      return await tempOutput.readAsBytes();
    } finally {
      // Clean up temporary files
      if (await tempInput.exists()) await tempInput.delete();
      if (await tempOutput.exists()) await tempOutput.delete();
    }
  }
}
