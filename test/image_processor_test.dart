import 'dart:typed_data';
import 'package:blog_builder/blog_builder.dart';
import 'package:file/memory.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';

void main() {
  group('ImageOptimizationConfig', () {
    test('creates default config with disabled state', () {
      final config = ImageOptimizationConfig();
      expect(config.enabled, false);
      expect(config.png.enabled, true);
      expect(config.png.level, 6);
      expect(config.jpeg.enabled, true);
      expect(config.jpeg.quality, 85);
    });

    test('parses config from map', () {
      final config = ImageOptimizationConfig.fromMap({
        'enabled': true,
        'png': {
          'enabled': true,
          'compression_level': 9,
          'strip_metadata': true,
        },
        'jpeg': {
          'enabled': true,
          'quality': 75,
        },
      });

      expect(config.enabled, true);
      expect(config.png.enabled, true);
      expect(config.png.level, 9);
      expect(config.jpeg.enabled, true);
      expect(config.jpeg.quality, 75);
    });

    test('handles null map with defaults', () {
      final config = ImageOptimizationConfig.fromMap(null);
      expect(config.enabled, false);
      expect(config.png.level, 6);
    });
  });

  group('ImageProcessor', () {
    late MemoryFileSystem fs;
    late ImageProcessor processor;

    setUp(() {
      fs = MemoryFileSystem();
      processor = ImageProcessor(
        config: ImageOptimizationConfig(
          enabled: true,
          png: PngConfig(enabled: true, level: 6),
          jpeg: JpegConfig(enabled: true, quality: 85),
        ),
      );
    });

    test('isImageFile identifies PNG files', () {
      expect(processor.isImageFile('test.png'), true);
      expect(processor.isImageFile('test.PNG'), true);
      expect(processor.isImageFile('/path/to/image.png'), true);
    });

    test('isImageFile identifies JPEG files', () {
      expect(processor.isImageFile('test.jpg'), true);
      expect(processor.isImageFile('test.jpeg'), true);
      expect(processor.isImageFile('TEST.JPG'), true);
    });

    test('isImageFile rejects non-image files', () {
      expect(processor.isImageFile('test.txt'), false);
      expect(processor.isImageFile('test.css'), false);
      expect(processor.isImageFile('test.html'), false);
      expect(processor.isImageFile('test.md'), false);
    });

    test('isPng correctly identifies PNG files', () {
      expect(processor.isPng('test.png'), true);
      expect(processor.isPng('test.PNG'), true);
      expect(processor.isPng('test.jpg'), false);
    });

    test('isJpeg correctly identifies JPEG files', () {
      expect(processor.isJpeg('test.jpg'), true);
      expect(processor.isJpeg('test.jpeg'), true);
      expect(processor.isJpeg('test.JPEG'), true);
      expect(processor.isJpeg('test.png'), false);
    });

    test('processes PNG image successfully', () async {
      // Create a simple test PNG image
      final image = img.Image(width: 100, height: 100);
      img.fill(image, color: img.ColorRgba8(255, 0, 0, 255));
      final pngBytes = img.encodePng(image);

      // Create input file
      final inputFile = fs.file('/input/test.png');
      inputFile.parent.createSync(recursive: true);
      inputFile.writeAsBytesSync(pngBytes);

      // Create output path
      final outputFile = fs.file('/output/test.png');
      outputFile.parent.createSync(recursive: true);

      // Process the image
      final result = await processor.processImage(inputFile, outputFile);

      expect(result.success, true);
      expect(result.originalSize, pngBytes.length);
      expect(outputFile.existsSync(), true);
    });

    test('processes JPEG image successfully', () async {
      // Create a simple test JPEG image
      final image = img.Image(width: 100, height: 100);
      img.fill(image, color: img.ColorRgba8(0, 255, 0, 255));
      final jpegBytes = img.encodeJpg(image, quality: 100);

      // Create input file
      final inputFile = fs.file('/input/test.jpg');
      inputFile.parent.createSync(recursive: true);
      inputFile.writeAsBytesSync(jpegBytes);

      // Create output path
      final outputFile = fs.file('/output/test.jpg');
      outputFile.parent.createSync(recursive: true);

      // Process the image
      final result = await processor.processImage(inputFile, outputFile);

      expect(result.success, true);
      expect(result.originalSize, jpegBytes.length);
      expect(outputFile.existsSync(), true);
    });

    test('throws on invalid/empty image', () async {
      // Create an empty file
      final inputFile = fs.file('/input/empty.png');
      inputFile.parent.createSync(recursive: true);
      inputFile.writeAsBytesSync(Uint8List(0));

      final outputFile = fs.file('/output/empty.png');
      outputFile.parent.createSync(recursive: true);

      // Process should throw
      expect(
        () => processor.processImage(inputFile, outputFile),
        throwsA(anything),
      );
    });

    test('throws on corrupt image data', () async {
      // Create a file with random bytes
      final inputFile = fs.file('/input/corrupt.png');
      inputFile.parent.createSync(recursive: true);
      inputFile.writeAsBytesSync(Uint8List.fromList([1, 2, 3, 4, 5]));

      final outputFile = fs.file('/output/corrupt.png');
      outputFile.parent.createSync(recursive: true);

      // Process should throw
      expect(
        () => processor.processImage(inputFile, outputFile),
        throwsA(anything),
      );
    });

    test('skips unsupported formats', () async {
      // Create a GIF file (not supported in Phase 1)
      final inputFile = fs.file('/input/test.gif');
      inputFile.parent.createSync(recursive: true);
      inputFile.writeAsBytesSync(Uint8List.fromList([71, 73, 70, 56, 57, 97])); // GIF header

      final outputFile = fs.file('/output/test.gif');
      outputFile.parent.createSync(recursive: true);

      final result = await processor.processImage(inputFile, outputFile);

      // Should succeed (copied as-is) but with no compression
      expect(result.success, true);
      expect(result.savings, 0);
    });
  });

  group('ImageProcessingStats', () {
    test('tracks statistics correctly', () {
      final stats = ImageProcessingStats();

      stats.addResult(ImageProcessResult(
        inputPath: '/test1.png',
        outputPath: '/out/test1.png',
        originalSize: 1000,
        compressedSize: 700,
        success: true,
      ));

      stats.addResult(ImageProcessResult(
        inputPath: '/test2.png',
        outputPath: '/out/test2.png',
        originalSize: 2000,
        compressedSize: 1500,
        success: true,
      ));

      expect(stats.totalImages, 2);
      expect(stats.processedImages, 2);
      expect(stats.totalOriginalSize, 3000);
      expect(stats.totalCompressedSize, 2200);
      expect(stats.totalSavings, 800);
    });

    test('calculates savings percentage correctly', () {
      final stats = ImageProcessingStats();

      stats.addResult(ImageProcessResult(
        inputPath: '/test.png',
        outputPath: '/out/test.png',
        originalSize: 1000,
        compressedSize: 500,
        success: true,
      ));

      expect(stats.totalImages, 1);
      expect(stats.processedImages, 1);
      expect(stats.savingsPercent, 50.0);
    });

    test('formatBytes formats correctly', () {
      expect(ImageProcessingStats.formatBytes(500), '500 B');
      expect(ImageProcessingStats.formatBytes(1024), '1.0 KB');
      expect(ImageProcessingStats.formatBytes(1536), '1.5 KB');
      expect(ImageProcessingStats.formatBytes(1048576), '1.00 MB');
      expect(ImageProcessingStats.formatBytes(1572864), '1.50 MB');
    });
  });

  group('ImageProcessResult', () {
    test('calculates savings correctly', () {
      final result = ImageProcessResult(
        inputPath: '/test.png',
        outputPath: '/out/test.png',
        originalSize: 1000,
        compressedSize: 700,
        success: true,
      );

      expect(result.savings, 300);
      expect(result.savingsPercent, 30.0);
    });

    test('handles zero original size', () {
      final result = ImageProcessResult(
        inputPath: '/test.png',
        outputPath: '/out/test.png',
        originalSize: 0,
        compressedSize: 0,
        success: true,
      );

      expect(result.savings, 0);
      expect(result.savingsPercent, 0.0);
    });
  });
}
