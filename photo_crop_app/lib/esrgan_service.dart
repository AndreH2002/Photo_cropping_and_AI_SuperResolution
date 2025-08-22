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

  /// Enhance an image file
  Future<File?> enhanceFile(File inputImage) async {
    if (_modelPath == null) {
      debugPrint("❌ Model not loaded");
      return null;
    }

    final decoded = img.decodeImage(await inputImage.readAsBytes());
    if (decoded == null) return null;

    const int tileSize = 128;
    const int scale = 4;
    final inputH = decoded.height;
    final inputW = decoded.width;
    final outputH = inputH * scale;
    final outputW = inputW * scale;

    // Prepare tile parameters
    final List<Map<String, dynamic>> tileParams = [];
    for (int y = 0; y < inputH; y += tileSize) {
      for (int x = 0; x < inputW; x += tileSize) {
        var w = (x + tileSize <= inputW) ? tileSize : (inputW - x);
        var h = (y + tileSize <= inputH) ? tileSize : (inputH - y);
        

        //this pads the edges to multiples of 4 to avoid mismatched tiles
        if (w % scale != 0) {
          w += scale - (w % scale);
        }
        if(h % scale != 0) {
          h += scale - (h % scale);
        }

        final tile = _cropImage(decoded, x, y, w, h);

        tileParams.add({
          "tileBytes": Uint8List.fromList(img.encodePng(tile)),
          "modelPath": _modelPath!,
          "x": x,
          "y": y,
        });
      }
    }

    // Limit concurrency to 2 tiles at once
    final maxConcurrent = 2;
    debugPrint("⚡ Running with concurrency = $maxConcurrent");

    final finalImage = img.Image(width: outputW, height: outputH);

    await _processTilesInParallel(tileParams, maxConcurrent, finalImage, 4);

    // Merge results
    /** 
    for (final r in results) {
      pasteImage(finalImage, r.image, r.x * scale, r.y * scale);
    }
    */

    // Save enhanced file
    final enhancedPath =
        '${inputImage.parent.path}/enhanced_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final enhancedFile =
        File(enhancedPath)..writeAsBytesSync(img.encodeJpg(finalImage, quality: 100));

    return enhancedFile;
  }

  /// Helper: Run tiles in parallel with limited concurrency
  Future <void> _processTilesInParallel (

    List<Map<String, dynamic>> tiles,
    int maxConcurrent,
    img.Image finalImage,
    int scale) async {
  
  
    //final results = <_TileResult>[];
    final active = <Future<_TileResult>>[];

    int nextTileIndex = 0;

    while (nextTileIndex < tiles.length || active.isNotEmpty) {
      // Launch new tiles while under max concurrency
      while (nextTileIndex < tiles.length && active.length < maxConcurrent) {
       final tileParams = tiles[nextTileIndex];
        active.add(compute(_processTile, tileParams));
        nextTileIndex++;
    }

    // Wait for any tile to finish
    final finishedIndex = await Future.any(  
      active.map((f) async => active.indexOf(f)).toList(),
    );

    final finished = await active[finishedIndex];
    //results.add(finished);

    // Remove finished future from active
    active.removeAt(finishedIndex);
    
    // Paste immediately
    pasteImage(finalImage, finished.image, finished.x * scale, finished.y * scale);
  }

  //return results;
}

}

/// Tile result container
class _TileResult {
  final img.Image image;
  final int x;
  final int y;

  _TileResult({required this.image, required this.x, required this.y});
}

/// Runs one tile in an isolate
Future<_TileResult> _processTile(Map<String, dynamic> tileParams) async {
  final tileBytes = tileParams['tileBytes'] as Uint8List;
  final modelPath = tileParams['modelPath'] as String;
  final x = tileParams['x'] as int;
  final y = tileParams['y'] as int;

  final tile = img.decodeImage(tileBytes)!;
  final interpreter = Interpreter.fromFile(File(modelPath));

  final inputTensor = _imageToNestedFloat32(tile);
  const scale = 4;
  final outputBuffer = List.generate(
    1,
    (_) => List.generate(
      tile.height * scale,
      (_) => List.generate(tile.width * scale, (_) => List.filled(3, 0.0)),
    ),
  );

  interpreter.run(inputTensor, outputBuffer);
  interpreter.close();

  final enhancedTile = _nestedOutputToImage(outputBuffer);
  return _TileResult(image: enhancedTile, x: x, y: y);
}

/// Converts img.Image to nested float [1,H,W,3]
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

/// Converts nested output [1,H,W,3] to img.Image
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

/// Crops an image
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
