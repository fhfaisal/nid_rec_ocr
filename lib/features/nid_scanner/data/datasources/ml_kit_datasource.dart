import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class MLKitDataSource {
  final TextRecognizer _latinRecognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );
  final TextRecognizer _devanagariRecognizer = TextRecognizer(
    script: TextRecognitionScript.devanagiri,
  );

  Future<String> recognizeText(File image) async {
    final inputImage = InputImage.fromFile(image);
    final results = await Future.wait([
      _latinRecognizer.processImage(inputImage),
      _devanagariRecognizer.processImage(inputImage),
    ]);

    final latinText = results[0].text;
    final bengaliText = results[1].text;

    return '$bengaliText\n$latinText';
  }

  Future<void> close() async {
    await _latinRecognizer.close();
    await _devanagariRecognizer.close();
  }
}
