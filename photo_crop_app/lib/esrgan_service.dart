import 'dart:io';

import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:flutter/foundation.dart';

class ESRGAN_Service {
  late Interpreter _interpreter;

  ESRGAN_Service();

  Future<void> loadModel() async {
    try {
      final options = InterpreterOptions();
      if (Platform.isIOS) {
        options.addDelegate(GpuDelegate());
      } else if (Platform.isAndroid) {
        options.addDelegate(GpuDelegateV2());
      }
      _interpreter = await Interpreter.fromAsset('assets/esrgan.tflite', options: options);
    } catch (e) {
      debugPrint('Error loading ESRGAN model: $e');
    }
  }

  Future<File?> enhanceFile(File inputImage) async {
    return compute(_enhanceInIsolate, _EnhanceParams(inputImage.path));
  }

  /// These two helper methods should be static so isolate can use them
  static List<List<List<List<double>>>> _imageToByteListFloat32(img.Image image) {
    return [
      List.generate(
        image.height,
        (y) => List.generate(
          image.width,
          (x) {
            final pixel = image.getPixel(x, y);
            return [pixel.r / 255.0, pixel.g / 255.0, pixel.b / 255.0];
          },
        ),
      ),
    ];
  }

  static img.Image _byteListToImage(List output) {
    final height = output.length;
    final width = output[0].length;
    final outImage = img.Image(width: width, height: height);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final r = (output[y][x][0] * 255).clamp(0, 255).toInt();
        final g = (output[y][x][1] * 255).clamp(0, 255).toInt();
        final b = (output[y][x][2] * 255).clamp(0, 255).toInt();
        outImage.setPixelRgba(x, y, r, g, b, 255);
      }
    }
    return outImage;
  }
}


Future<File?> _enhanceInIsolate(_EnhanceParams params) async {
  try {
    // Load model inside isolate
    final interpreter = await Interpreter.fromAsset('esrgan.tflite');

    // Read and decode image
    final inputFile = File(params.imagePath);
    final bytes = await inputFile.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    // Prepare input tensor
    var inputTensor = ESRGAN_Service._imageToByteListFloat32(decoded);

    // Prepare output tensor
    var outputShape = interpreter.getOutputTensor(0).shape;
    var output = List.generate(
      outputShape[1],
      (_) => List.generate(
        outputShape[2],
        (_) => List.filled(outputShape[3], 0.0),
      ),
    );

    // Run inference
    interpreter.run(inputTensor, output);

    // Convert output tensor back to image
    img.Image enhancedImage = ESRGAN_Service._byteListToImage(output);

    // Save the enhanced image
    final enhancedPath =
        '${inputFile.parent.path}/enhanced_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final enhancedFile = File(enhancedPath)
      ..writeAsBytesSync(img.encodeJpg(enhancedImage, quality: 100));

    return enhancedFile;
  } catch (e) {
    debugPrint("❌ ESRGAN enhancement isolate failed: $e");
    return null;
  }
}

class _EnhanceParams {
  final String imagePath;
  _EnhanceParams(this.imagePath);
}