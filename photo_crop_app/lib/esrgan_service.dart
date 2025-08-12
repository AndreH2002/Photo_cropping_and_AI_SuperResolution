import 'dart:io';
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

  /// Run enhancement in isolate (CPU only)
  Future<File?> enhanceFile(File inputImage) async {
    if (_modelPath == null) {
      debugPrint("❌ Model not loaded");
      return null;
    }
    return compute(_enhanceInIsolate, {
      "imagePath": inputImage.path,
      "modelPath": _modelPath!,
    });
  }
}

/// CPU‑only isolate
Future<File?> _enhanceInIsolate(Map<String, String> params) async {
  Interpreter? interpreter;
  try {
    final options = InterpreterOptions();
    interpreter = Interpreter.fromFile(
      File(params["modelPath"]!),
      options: options,
    );

    final inputFile = File(params["imagePath"]!);
    final decoded = img.decodeImage(await inputFile.readAsBytes());
    if (decoded == null) return null;

    // 🔄 Use tiling enhancement for memory safety
    final enhancedImage = await _enhanceWithTiling(decoded, interpreter);

    interpreter.close();

    final enhancedPath =
        '${inputFile.parent.path}/enhanced_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final enhancedFile = File(enhancedPath)
      ..writeAsBytesSync(img.encodeJpg(enhancedImage, quality: 100));

    debugPrint("✅ Enhancement (CPU) done");
    return enhancedFile;
  } catch (e) {
    debugPrint("❌ ESRGAN CPU isolate failed: $e");
    interpreter?.close();
    return null;
  }
}

/// Tiling enhancement to reduce memory usage
Future<img.Image> _enhanceWithTiling(
    img.Image inputImage, Interpreter interpreter) async {
  final tileSize = 128;
  final overlap = 16;
  final scaleFactor = 4;

  final width = inputImage.width;
  final height = inputImage.height;

  // Output image (upscaled size)
  img.Image outputImage =
      img.Image(width: width * scaleFactor, height: height * scaleFactor);

  // Weight map to blend overlapping tiles
  final weights = List.generate(
    outputImage.height,
    (_) => List.filled(outputImage.width, 0.0),
  );

  // Calculate step size (tileSize minus 2*overlap)
  final step = tileSize - overlap * 2;

  // Loop over tiles, ensuring full coverage including edges
  for (int y = 0;; y += step) {
    if (y + tileSize >= height) {
      y = height - tileSize; // Clamp last tile to edge
      if (y < 0) y = 0; // Clamp for very small images
    }
    for (int x = 0;; x += step) {
      if (x + tileSize >= width) {
        x = width - tileSize;
        if (x < 0) x = 0;
      }

      // Clamp crop rectangle inside input image bounds
      int startX = x;
      int startY = y;
      int tileW = tileSize;
      int tileH = tileSize;

      // Crop tile
      img.Image tile = cropImage(inputImage, startX, startY, tileW, tileH);

      // Enhance tile with model (returns upscaled tile)
      img.Image enhancedTile = await _runTileThroughESRGAN(tile, interpreter);

      // Paste enhanced tile into output image at scaled position
      int destX = startX * scaleFactor;
      int destY = startY * scaleFactor;

      for (int yy = 0; yy < enhancedTile.height; yy++) {
        for (int xx = 0; xx < enhancedTile.width; xx++) {
          int px = destX + xx;
          int py = destY + yy;

          if (px >= 0 &&
              px < outputImage.width &&
              py >= 0 &&
              py < outputImage.height) {
            final newPixel = enhancedTile.getPixel(xx, yy);
            final existingPixel = outputImage.getPixel(px, py);
            double weight = 1.0;

            // Weighted blend to smooth seams
            int r = (((existingPixel.r * weights[py][px]) +
                        (newPixel.r * weight)) /
                    (weights[py][px] + weight))
                .toInt();
            int g = (((existingPixel.g * weights[py][px]) +
                        (newPixel.g * weight)) /
                    (weights[py][px] + weight))
                .toInt();
            int b = (((existingPixel.b * weights[py][px]) +
                        (newPixel.b * weight)) /
                    (weights[py][px] + weight))
                .toInt();

            outputImage.setPixelRgba(px, py, r, g, b, 255);

            weights[py][px] += weight;
          }
        }
      }

      // Break inner loop if we've reached the right edge
      if (x + tileSize >= width) break;
    }
    // Break outer loop if we've reached the bottom edge
    if (y + tileSize >= height) break;
  }

  return outputImage;
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
            pixel.r / 255.0,
            pixel.g / 255.0,
            pixel.b / 255.0,
          ];
        },
      ),
    ),
  );
}

/// Converts Float32 [H, W, 3] back to img.Image
img.Image _float32ListToImage(Float32List buffer, int height, int width, int channels) {
  final outImage = img.Image(width: width, height: height);

  int index = 0;
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final r = (buffer[index++] * 255).clamp(0, 255).toInt();
      final g = (buffer[index++] * 255).clamp(0, 255).toInt();
      final b = (buffer[index++] * 255).clamp(0, 255).toInt();
      outImage.setPixelRgba(x, y, r, g, b, 255);
    }
  }

  return outImage;
}

/// Runs a single tile through ESRGAN
Future<img.Image> _runTileThroughESRGAN(
  img.Image tile,
  Interpreter interpreter,
) async {
  // 1. Allocate tensors before reading shapes
  try {
    interpreter.allocateTensors();
    debugPrint("Tensors allocated successfully");
} catch (e) {
  debugPrint("Failed to allocate tensors: $e");
}

  // 2. Get input/output tensor shapes AFTER allocation
  final inputShape = interpreter.getInputTensor(0).shape;   // e.g. [1, 144, 144, 3]
  final outputShape = interpreter.getOutputTensor(0).shape; // e.g. [1, 576, 576, 3]

  final inputH = inputShape[1];
  final inputW = inputShape[2];
  final outputH = outputShape[1];
  final outputW = outputShape[2];
  final outputC = outputShape[3]; // usually 3 (RGB)

  // Debug prints (optional)
  debugPrint('Input shape: $inputShape');
  debugPrint('Output shape: $outputShape');

  // 3. Resize input tile to model input size
  final resizedInput = img.copyResize(
    tile,
    width: inputW,
    height: inputH,
    interpolation: img.Interpolation.linear,
  );

  // 4. Convert resized input image to Float32 tensor of shape [1, H, W, 3]
  final inputTensor = _imageToNestedFloat32(resizedInput);

  // 5. Allocate output buffer exactly matching output shape [1, outH, outW, outC]
  final outputBuffer = List.generate(
    1,
    (_) => List.generate(
      outputH,
      (_) => List.generate(
        outputW,
        (_) => List.filled(outputC, 0.0),
      ),
    ),
  );

  // 6. Run interpreter with correct input and output buffers
  interpreter.run(inputTensor, outputBuffer);

  // 7. Convert output buffer (nested list) to flat Float32List for image conversion
  final flatOutput = Float32List(outputH * outputW * outputC);
  int idx = 0;
  for (int y = 0; y < outputH; y++) {
    for (int x = 0; x < outputW; x++) {
      for (int c = 0; c < outputC; c++) {
        flatOutput[idx++] = outputBuffer[0][y][x][c];
      }
    }
  }

  // 8. Convert model output tensor to image using output dimensions
  final enhancedTile = _float32ListToImage(flatOutput, outputH, outputW, outputC);

  // 9. Resize back to original tile size (downscale) to keep final image size consistent
  final finalTile = img.copyResize(
    enhancedTile,
    width: tile.width,
    height: tile.height,
    interpolation: img.Interpolation.linear,
  );

  return finalTile;
}




/// Crops image
img.Image cropImage(img.Image src, int x, int y, int w, int h) {
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

/// Pastes one image into another
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
