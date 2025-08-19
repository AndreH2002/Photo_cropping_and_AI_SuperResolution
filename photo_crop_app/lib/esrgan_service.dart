import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:flutter/foundation.dart';

class ESRGAN_Service {
  String? _modelPath;

  /// Load model once
  Future<void> loadModel() async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      final byteData = await rootBundle.load('assets/esrgan.tflite');
      final tempDir = await getTemporaryDirectory();
      final modelFile = File('${tempDir.path}/esrgan.tflite');
      await modelFile.writeAsBytes(byteData.buffer.asUint8List());
      _modelPath = modelFile.path;
      debugPrint('✅ ESRGAN model loaded at $_modelPath');
    } catch (e) {
      debugPrint('❌ Error loading ESRGAN model: $e');
    }
  }

  /// Enhance with tiling
  Future<File?> enhanceFile(File inputImage) async {
    if (_modelPath == null) {
      debugPrint("❌ Model not loaded");
      return null;
    }
    return compute(_enhanceWithTiling, {
      "imagePath": inputImage.path,
      "modelPath": _modelPath!,
    });
  }
}

Future<File?> _enhanceWithTiling(Map<String, String> params) async {
  Interpreter? interpreter;
  try {
    final modelFile = File(params["modelPath"]!);
    debugPrint(
        'Model file exists: ${await modelFile.exists()}, size: ${await modelFile.length()}');

    interpreter = Interpreter.fromFile(modelFile);

    final inputFile = File(params["imagePath"]!);
    final decoded = img.decodeImage(await inputFile.readAsBytes());
    if (decoded == null) return null;

    const int tileSize = 512;
    const int scale = 4;
    final inputH = decoded.height;
    final inputW = decoded.width;
    final outputH = inputH * scale;
    final outputW = inputW * scale;
    final outputC = 3;

    // Prepare final output image
    final finalImage = img.Image(width: outputW, height: outputH);

    for (int y = 0; y < inputH; y += tileSize) {
      for (int x = 0; x < inputW; x += tileSize) {
        final w = (x + tileSize <= inputW) ? tileSize : (inputW - x);
        final h = (y + tileSize <= inputH) ? tileSize : (inputH - y);

        final tile = _cropImage(decoded, x, y, w, h);

        // Resize interpreter input
        interpreter.resizeInputTensor(0, [1, h, w, 3]);
        interpreter.allocateTensors();

        final inputTensor = _imageToNestedFloat32(tile);

        // Output buffer for this tile
        final outputBuffer = List.generate(
          1,
          (_) => List.generate(
            h * scale,
            (_) => List.generate(
              w * scale,
              (_) => List.filled(outputC, 0.0),
            ),
          ),
        );

        interpreter.run(inputTensor, outputBuffer);

        final enhancedTile = _nestedOutputToImage(outputBuffer);

        // Paste enhanced tile into final image
        pasteImage(finalImage, enhancedTile, x * scale, y * scale);
      }
    }

    final enhancedPath =
        '${inputFile.parent.path}/enhanced_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final enhancedFile =
        File(enhancedPath)..writeAsBytesSync(img.encodeJpg(finalImage, quality: 100));

    interpreter.close();
    return enhancedFile;
  } catch (e) {
    debugPrint("❌ ESRGAN CPU isolate failed: $e");
    interpreter?.close();
    return null;
  }
}

/// Converts img.Image to nested Float32 [1, H, W, 3]
List _imageToNestedFloat32(img.Image image) {
  final width = image.width;
  final height = image.height;
  return List.generate(
    1,
    (_) => List.generate(
      height,
      (y) => List.generate(
        width,
        (x) {
          final pixel = image.getPixel(x, y);
          return [
            pixel.r.toDouble(),
            pixel.g.toDouble(),
            pixel.b.toDouble(),
          ];
        },
      ),
    ),
  );
}

/// Converts nested output [1,H,W,3] from TFLite directly to img.Image
img.Image _nestedOutputToImage(List outputBuffer) {
  final batch = outputBuffer[0];
  final height = batch.length;
  final width = batch[0].length;

  final outImage = img.Image(width: width, height: height);

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final pixel = batch[y][x];
      final r = pixel[0].clamp(0, 255).toInt();
      final g = pixel[1].clamp(0, 255).toInt();
      final b = pixel[2].clamp(0, 255).toInt();
      outImage.setPixelRgba(x, y, r, g, b, 255);
    }
  }

  return outImage;
}

/// Copy
img.Image _cropImage(img.Image src, int x, int y, int w, int h) {
  final cropped = img.Image(width: w, height: h);
  for (int yy = 0; yy < h; yy++) {
    for (int xx = 0; xx < w; xx++) {
      final srcX = x + xx;
      final srcY = y + yy;
      if (srcX >= 0 && srcX < src.width && srcY >= 0 && srcY < src.height) {
        cropped.setPixel(xx, yy, src.getPixel(srcX, srcY));
      }
    }
  }
  return cropped;
}

/// Paste
void pasteImage(img.Image dest, img.Image src, int dstX, int dstY) {
  for (int y = 0; y < src.height; y++) {
    for (int x = 0; x < src.width; x++) {
      final dx = dstX + x;
      final dy = dstY + y;
      if (dx >= 0 && dx < dest.width && dy >= 0 && dy < dest.height) {
        dest.setPixel(dx, dy, src.getPixel(x, y));
      }
    }
  }
}
