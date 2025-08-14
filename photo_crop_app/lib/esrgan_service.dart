import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:flutter/foundation.dart';

class ESRGAN_Service {
  String? _modelPath;

  ///Load model
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

  /// Run the enhancement in the isolate, right now this is only cpu
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

Future<File?> _enhanceInIsolate(Map<String, String> params) async {
  Interpreter? interpreter;
  try {
    final modelFile = File(params["modelPath"]!);
    debugPrint(
        'Model file exists: ${await modelFile.exists()}, size: ${await modelFile.length()}');

    interpreter = Interpreter.fromFile(modelFile);

    final inputFile = File(params["imagePath"]!);
    final decoded = img.decodeImage(await inputFile.readAsBytes());
    if (decoded == null) return null;

    final inputH = decoded.height;
    final inputW = decoded.width;

    //1. Resize interpreter input tensor dynamically 
    interpreter.resizeInputTensor(0, [1, inputH, inputW, 3]);
    interpreter.allocateTensors();

    debugPrint('Interpreter input shape: ${interpreter.getInputTensor(0).shape}');
    debugPrint('Interpreter output shape (reported): ${interpreter.getOutputTensor(0).shape}');

    // 2. Prepare the normalized input tensor [-1,1] 
    final inputTensor = _imageToNestedFloat32(decoded);

    // 3. Allocate nested output buffer 
    const scale = 4; 
    final outputH = inputH * scale;
    final outputW = inputW * scale;
    final outputC = 3;

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

    //4. Run the interpreter
    interpreter.run(inputTensor, outputBuffer);

    // 5. Convert output to image ---
    final enhancedImage = _nestedOutputToImage(outputBuffer);


    // 6. Save enhanced image ---
    final enhancedPath =
        '${inputFile.parent.path}/enhanced_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final enhancedFile =
        File(enhancedPath)..writeAsBytesSync(img.encodeJpg(enhancedImage, quality: 100));

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
            pixel.r / 127.5 - 1.0,
            pixel.g / 127.5 - 1.0,
            pixel.b / 127.5 - 1.0,
          ];
        },
      ),
    ),
  );
}

/// Converts nested output [1,H,W,3] from TFLite directly to img.Image
img.Image _nestedOutputToImage(List outputBuffer) {
  final nested = outputBuffer;
  final batch = nested[0];
  final height = batch.length;
  final width = batch[0].length;

  final outImage = img.Image(width: width, height: height);

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final pixel = batch[y][x];
      final r = ((pixel[0] + 1.0) * 0.5 * 255).clamp(0, 255).toInt();
      final g = ((pixel[1] + 1.0) * 0.5 * 255).clamp(0, 255).toInt();
      final b = ((pixel[2] + 1.0) * 0.5 * 255).clamp(0, 255).toInt();
      outImage.setPixelRgba(x, y, r, g, b, 255);
    }
  }

  return outImage;
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
