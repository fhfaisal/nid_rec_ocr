import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../manager/scanner_provider.dart';
import '../manager/scanner_state.dart';
import '../widgets/nid_info_card.dart';
import '../../domain/entities/nid_card.dart';
import 'camera_page.dart';

class ScannerPage extends ConsumerStatefulWidget {
  const ScannerPage({super.key});

  @override
  ConsumerState<ScannerPage> createState() => _ScannerPageState();
}

enum ScannerSide { front, back }

class _ScannerPageState extends ConsumerState<ScannerPage> {
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage(ImageSource source, ScannerSide side) async {
    try {
      String? imagePath;

      if (source == ImageSource.camera) {
        imagePath = await Navigator.push<String>(
          context,
          MaterialPageRoute(
            builder: (context) => const CameraPage(),
          ),
        );
      } else {
        final XFile? pickedFile = await _picker.pickImage(source: source);
        if (pickedFile != null) {
          imagePath = await _cropImage(pickedFile.path);
        }
      }

      if (imagePath != null) {
        final imageFile = File(imagePath);
        final notifier = ref.read(scannerProvider.notifier);
        if (side == ScannerSide.front) {
          notifier.setImage(imageFile);
          await notifier.scanImage(imageFile);
        } else {
          notifier.setBackImage(imageFile);
          await notifier.scanBackSide(imageFile);
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking image: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<String?> _cropImage(String path) async {
    final croppedFile = await ImageCropper().cropImage(
      sourcePath: path,
      aspectRatio: const CropAspectRatio(ratioX: 3.2, ratioY: 2.0),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop NID Card',
          toolbarColor: Colors.green,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.ratio3x2,
          lockAspectRatio: true,
        ),
        IOSUiSettings(
          title: 'Crop NID Card',
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
        ),
      ],
    );
    return croppedFile?.path;
  }

  void _showImageSourceDialog(ScannerSide side) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Select Image Source for ${side == ScannerSide.front ? "Front" : "Back"} Side'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Camera'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera, side);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery, side);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(scannerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('NID Scanner'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (state.image != null || state.backImage != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => ref.read(scannerProvider.notifier).clear(),
              tooltip: 'Clear All',
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: _buildImagePreview(state.image, 'Front Side')),
                  const SizedBox(width: 12),
                  Expanded(child: _buildImagePreview(state.backImage, 'Back Side')),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(child: _buildScanButton('Scan Front', () => _showImageSourceDialog(ScannerSide.front), Colors.green)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildScanButton('Scan Back', () => _showImageSourceDialog(ScannerSide.back), Colors.blue)),
                ],
              ),
              const SizedBox(height: 24),
              _buildStatusOrResults(state),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImagePreview(File? image, String label) {
    return Column(
      children: [
        Container(
          height: 120,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[400]!),
          ),
          child: image != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    image,
                    fit: BoxFit.cover,
                  ),
                )
              : Center(
                  child: Icon(Icons.credit_card, size: 40, color: Colors.grey[400]),
                ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildScanButton(String label, VoidCallback onPressed, Color color) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        backgroundColor: color,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildStatusOrResults(ScannerState state) {
    if (state.isProcessing) {
      return const Center(
        child: Column(
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Processing NID card...'),
          ],
        ),
      );
    } else if (state.nidData != null || state.backNidData != null) {
      return _buildCombinedResults(state);
    } else if (state.errorMessage != null) {
      return Center(
        child: Text(
          state.errorMessage!,
          style: const TextStyle(color: Colors.red),
          textAlign: TextAlign.center,
        ),
      );
    } else {
      return _buildEmptyState();
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          children: [
            Icon(Icons.info_outline, size: 60, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text(
              'Scan both sides of NID to get full data',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCombinedResults(ScannerState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (state.nidData != null) ...[
          const Text('Front Side Info:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _buildFrontResults(state.nidData!),
          const SizedBox(height: 24),
        ],
        if (state.backNidData != null) ...[
          const Text('Back Side Info (MRZ):', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _buildBackResults(state.backNidData!),
        ],
      ],
    );
  }

  Widget _buildFrontResults(NIDCard data) {
    return Column(
      children: [
        if (data.name != null)
          NIDInfoCard(
            icon: Icons.person,
            label: 'Name',
            value: data.name!,
            onCopy: () => _copyToClipboard(data.name!, 'Name'),
          ),
        if (data.nidNumber != null)
          NIDInfoCard(
            icon: Icons.badge,
            label: 'NID Number',
            value: data.nidNumber!,
            onCopy: () => _copyToClipboard(data.nidNumber!, 'NID Number'),
          ),
        if (data.dateOfBirth != null)
          NIDInfoCard(
            icon: Icons.cake,
            label: 'Date of Birth',
            value: data.dateOfBirth!,
            onCopy: () => _copyToClipboard(data.dateOfBirth!, 'Date of Birth'),
          ),
        if (data.fatherName != null)
          NIDInfoCard(
            icon: Icons.family_restroom,
            label: "Father's Name",
            value: data.fatherName!,
            onCopy: () => _copyToClipboard(data.fatherName!, "Father's Name"),
          ),
        if (data.motherName != null)
          NIDInfoCard(
            icon: Icons.family_restroom,
            label: "Mother's Name",
            value: data.motherName!,
            onCopy: () => _copyToClipboard(data.motherName!, "Mother's Name"),
          ),
      ],
    );
  }

  Widget _buildBackResults(NIDCard data) {
    return Column(
      children: [
        if (data.name != null)
          NIDInfoCard(
            icon: Icons.person,
            label: 'Name',
            value: data.name!,
            onCopy: () => _copyToClipboard(data.name!, 'Name'),
          ),
        if (data.gender != null)
          NIDInfoCard(
            icon: Icons.wc,
            label: 'Gender',
            value: data.gender!,
            onCopy: () => _copyToClipboard(data.gender!, 'Gender'),
          ),
        if (data.expiryDate != null)
          NIDInfoCard(
            icon: Icons.event_busy,
            label: 'Expiry Date',
            value: data.expiryDate!,
            onCopy: () => _copyToClipboard(data.expiryDate!, 'Expiry Date'),
          ),
        if (data.nationality != null)
          NIDInfoCard(
            icon: Icons.flag,
            label: 'Nationality',
            value: data.nationality!,
            onCopy: () => _copyToClipboard(data.nationality!, 'Nationality'),
          ),
        if (data.address != null)
          NIDInfoCard(
            icon: Icons.home,
            label: 'Address',
            value: data.address!,
            onCopy: () => _copyToClipboard(data.address!, 'Address'),
          ),
      ],
    );
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.green,
      ),
    );
  }
}
