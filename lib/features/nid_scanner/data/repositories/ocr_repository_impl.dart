import 'dart:io';
import '../../domain/repositories/ocr_repository.dart';
import '../datasources/ml_kit_datasource.dart';

class OCRRepositoryImpl implements OCRRepository {
  final MLKitDataSource dataSource;

  OCRRepositoryImpl(this.dataSource);

  @override
  Future<String> recognizeText(File image) {
    return dataSource.recognizeText(image);
  }

  @override
  Future<void> close() {
    return dataSource.close();
  }
}
