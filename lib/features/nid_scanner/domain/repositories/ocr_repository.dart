import 'dart:io';
import '../entities/nid_card.dart';

abstract class OCRRepository {
  Future<String> recognizeText(File image);
  Future<void> close();
}
