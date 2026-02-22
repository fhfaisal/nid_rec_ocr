import 'dart:io';
import '../../domain/entities/nid_card.dart';

class ScannerState {
  final File? image;
  final NIDCard? nidData;
  final File? backImage;
  final NIDCard? backNidData;
  final bool isProcessing;
  final String? errorMessage;

  ScannerState({
    this.image,
    this.nidData,
    this.backImage,
    this.backNidData,
    this.isProcessing = false,
    this.errorMessage,
  });

  ScannerState copyWith({
    File? image,
    NIDCard? nidData,
    File? backImage,
    NIDCard? backNidData,
    bool? isProcessing,
    String? errorMessage,
    bool clearImage = false,
    bool clearNidData = false,
    bool clearBackImage = false,
    bool clearBackNidData = false,
    bool clearErrorMessage = false,
  }) {
    return ScannerState(
      image: clearImage ? null : (image ?? this.image),
      nidData: clearNidData ? null : (nidData ?? this.nidData),
      backImage: clearBackImage ? null : (backImage ?? this.backImage),
      backNidData: clearBackNidData ? null : (backNidData ?? this.backNidData),
      isProcessing: isProcessing ?? this.isProcessing,
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
