import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class ImageProcessor {
  Future<File?> cropImage(File image, double viewportWidth, double viewportHeight) async {
    final Uint8List bytes = await image.readAsBytes();
    img.Image? originalImage = img.decodeImage(bytes);

    if (originalImage == null) return null;

    if (originalImage.exif.exifIfd.orientation != -1) {
      originalImage = img.bakeOrientation(originalImage);
    }

    final double viewportRatio = viewportWidth / viewportHeight;
    final double imageRatio = originalImage.width / originalImage.height;

    int cropWidth;
    int cropHeight;

    if (imageRatio < viewportRatio) {
      cropWidth = originalImage.width;
      cropHeight = (cropWidth / viewportRatio).round();
    } else {
      cropHeight = originalImage.height;
      cropWidth = (cropHeight * viewportRatio).round();
    }

    if (cropWidth > originalImage.width) cropWidth = originalImage.width;
    if (cropHeight > originalImage.height) cropHeight = originalImage.height;

    final int cropX = (originalImage.width - cropWidth) ~/ 2;
    final int cropY = (originalImage.height - cropHeight) ~/ 2;

    final img.Image croppedImage = img.copyCrop(
      originalImage,
      x: cropX,
      y: cropY,
      width: cropWidth,
      height: cropHeight,
    );

    final String dir = (await getApplicationDocumentsDirectory()).path;
    final String filename = 'cropped_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final String resultPath = path.join(dir, filename);

    final croppedFile = File(resultPath);
    await croppedFile.writeAsBytes(img.encodeJpg(croppedImage, quality: 90));
    return croppedFile;
  }
}
