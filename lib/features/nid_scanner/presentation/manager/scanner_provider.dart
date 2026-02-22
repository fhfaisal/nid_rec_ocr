import 'dart:developer';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../data/datasources/ml_kit_datasource.dart';
import '../../data/repositories/ocr_repository_impl.dart';
import '../../domain/usecases/scan_nid_usecase.dart';
import 'scanner_state.dart';

// Dependency injection providers
final mlKitDataSourceProvider = Provider((ref) => MLKitDataSource());

final ocrRepositoryProvider = Provider((ref) {
  final dataSource = ref.watch(mlKitDataSourceProvider);
  return OCRRepositoryImpl(dataSource);
});

final scanNIDUseCaseProvider = Provider((ref) {
  final repository = ref.watch(ocrRepositoryProvider);
  return ScanNIDUseCase(repository);
});

// State provider
final scannerProvider = StateNotifierProvider<ScannerNotifier, ScannerState>((ref) {
  final useCase = ref.watch(scanNIDUseCaseProvider);
  return ScannerNotifier(useCase);
});

class ScannerNotifier extends StateNotifier<ScannerState> {
  final ScanNIDUseCase _scanNIDUseCase;

  ScannerNotifier(this._scanNIDUseCase) : super(ScannerState());

  void setImage(File image) {
    state = state.copyWith(
      image: image,
      clearNidData: true,
      clearErrorMessage: true,
    );
  }

  void clear() {
    state = ScannerState();
  }

  Future<void> scanImage(File image) async {
    state = state.copyWith(isProcessing: true, clearErrorMessage: true);

    try {
      final nidData = await _scanNIDUseCase.execute(image);
      state = state.copyWith(nidData: nidData, isProcessing: false);
    } catch (e) {
      state = state.copyWith(
        errorMessage: 'Error scanning NID: $e',
        isProcessing: false,
      );
    }
  }

  void setBackImage(File image) {
    state = state.copyWith(
      backImage: image,
      clearBackNidData: true,
      clearErrorMessage: true,
    );
  }

  Future<void> scanBackSide(File image) async {
    state = state.copyWith(isProcessing: true, clearErrorMessage: true);

    try {
      final nidData = await _scanNIDUseCase.executeBackSide(image);
      state = state.copyWith(backNidData: nidData, isProcessing: false);
    } catch (e) {
      log('Error scanning NID Back Side: $e');
      state = state.copyWith(
        errorMessage: 'Error scanning NID Back Side: $e',
        isProcessing: false,
      );
    }
  }
}
