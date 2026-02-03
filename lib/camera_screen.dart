import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class CameraInstructionScreen extends StatefulWidget {
  const CameraInstructionScreen({super.key});

  @override
  State<CameraInstructionScreen> createState() => _CameraInstructionScreenState();
}

class _CameraInstructionScreenState extends State<CameraInstructionScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isTakingPicture = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _controller;
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        setState(() {
          _errorMessage = 'No camera found';
        });
        return;
      }

      final camera = _cameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );

      _controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _errorMessage = null;
        });
      }
    } catch (e) {
      debugPrint('Camera error: $e');
      setState(() {
        _errorMessage = 'Camera unavailable';
        _isInitialized = false;
      });
    }
  }

  Future<void> _takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized || _isTakingPicture) {
      return;
    }

    try {
      // Calculate viewport dimensions before async gap
      final Size screenSize = MediaQuery.of(context).size;
      final double viewportWidth = screenSize.width - 48; // Horizontal padding 24 * 2
      const double viewportHeight = 240;

      setState(() {
        _isTakingPicture = true;
      });

      final XFile picture = await _controller!.takePicture();

      // Process image in background (could be moved to isolate if performance is an issue)
      // Reading as bytes
      final File imageFile = File(picture.path);
      final Uint8List bytes = await imageFile.readAsBytes();
      img.Image? originalImage = img.decodeImage(bytes);

      String resultPath = picture.path;

      if (originalImage != null) {
        // Fix orientation (handle EXIF)
        if (originalImage.exif.exifIfd.orientation != -1) {
          originalImage = img.bakeOrientation(originalImage);
        }

        final double viewportRatio = viewportWidth / viewportHeight;
        final double imageRatio = originalImage.width / originalImage.height;

        int cropWidth;
        int cropHeight;

        // Logic for BoxFit.cover
        // If image is "taller" than viewport (ImageRatio < ViewportRatio):
        // Scale is determined by Width. Widths match. Heights: Image > Viewport.
        // So we keep full width, crop height.
        if (imageRatio < viewportRatio) {
          cropWidth = originalImage.width;
          cropHeight = (cropWidth / viewportRatio).round();
        } else {
          // Image is "wider" than viewport.
          // Scale is determined by Height. Heights match. Widths: Image > Viewport.
          // Keep full height, crop width.
          cropHeight = originalImage.height;
          cropWidth = (cropHeight * viewportRatio).round();
        }

        // Ensure crop dimensions don't exceed image dimensions (rounding errors)
        if (cropWidth > originalImage.width) cropWidth = originalImage.width;
        if (cropHeight > originalImage.height) cropHeight = originalImage.height;

        final int cropX = (originalImage.width - cropWidth) ~/ 2;
        final int cropY = (originalImage.height - cropHeight) ~/ 2;

        final img.Image croppedImage = img.copyCrop(originalImage, x: cropX, y: cropY, width: cropWidth, height: cropHeight);

        // Save cropped image
        final String dir = (await getApplicationDocumentsDirectory()).path;
        final String filename = 'cropped_${DateTime.now().millisecondsSinceEpoch}.jpg';
        resultPath = path.join(dir, filename);

        await File(resultPath).writeAsBytes(img.encodeJpg(croppedImage, quality: 90));
      }

      if (mounted) {
        Navigator.of(context).pop(resultPath);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTakingPicture = false;
        });
      }
    }
  }

  Future<void> _useFallbackCamera() async {
    final ImagePicker picker = ImagePicker();
    final XFile? photo = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 95,
    );

    if (photo != null && mounted) {
      Navigator.pop(context, photo.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 28),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Scan NID Card',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Camera Preview Card
                    Container(
                      width: double.infinity,
                      height: 240,
                      decoration: BoxDecoration(
                        color: Colors.grey[900],
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.green, width: 2),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: _buildCameraPreview(),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Status indicator
                    if (_isInitialized)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Camera Ready',
                            style: TextStyle(color: Colors.green, fontSize: 14),
                          ),
                        ],
                      ),

                    const SizedBox(height: 24),

                    // Instructions
                    const Text(
                      'Photography Tips',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),

                    _buildTipItem(
                      Icons.wb_sunny_outlined,
                      'Good Lighting',
                      'Ensure the card is well-lit with no shadows',
                    ),
                    _buildTipItem(
                      Icons.crop_free,
                      'Full Card Visible',
                      'Capture the entire card within the frame',
                    ),
                    _buildTipItem(
                      Icons.straighten,
                      'Keep Level',
                      'Hold your phone parallel to the card',
                    ),
                    _buildTipItem(
                      Icons.zoom_in,
                      'Fill the Frame',
                      'Get close so the card fills most of the preview',
                    ),
                    _buildTipItem(
                      Icons.blur_off,
                      'Sharp & Clear',
                      'Make sure text is readable and not blurry',
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // Bottom button
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  if (_isInitialized)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isTakingPicture ? null : _takePicture,
                        icon: _isTakingPicture
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.camera, size: 24),
                        label: Text(
                          _isTakingPicture ? 'Capturing...' : 'Capture Photo',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    )
                  else if (_errorMessage != null)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _useFallbackCamera,
                        icon: const Icon(Icons.camera_alt, size: 24),
                        label: const Text(
                          'Use System Camera',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (_errorMessage != null) {
      return Container(
        color: Colors.grey[900],
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.camera_alt_outlined,
                size: 60,
                color: Colors.orange[300],
              ),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: TextStyle(
                  color: Colors.orange[300],
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Use system camera instead',
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isInitialized || _controller == null) {
      return Container(
        color: Colors.grey[900],
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: Colors.green),
              const SizedBox(height: 16),
              Text(
                'Initializing camera...',
                style: TextStyle(color: Colors.grey[400]),
              ),
            ],
          ),
        ),
      );
    }

    // Show camera preview with overlay
    return Stack(
      fit: StackFit.expand,
      children: [
        // Camera preview
        FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _controller!.value.previewSize!.height,
            height: _controller!.value.previewSize!.width,
            child: CameraPreview(_controller!),
          ),
        ),

        // Overlay guide
        CustomPaint(
          painter: CardFramePainter(),
        ),

        // Instruction overlay
        Positioned(
          bottom: 16,
          left: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Position NID card to fill the frame',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTipItem(IconData icon, String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: Colors.green[300], size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CardFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.green.withOpacity(0.8)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    // Draw corner brackets
    const cornerLength = 30.0;
    const margin = 20.0;

    // Top-left
    canvas.drawLine(
      const Offset(margin, margin + cornerLength),
      const Offset(margin, margin),
      paint,
    );
    canvas.drawLine(
      const Offset(margin, margin),
      const Offset(margin + cornerLength, margin),
      paint,
    );

    // Top-right
    canvas.drawLine(
      Offset(size.width - margin - cornerLength, margin),
      Offset(size.width - margin, margin),
      paint,
    );
    canvas.drawLine(
      Offset(size.width - margin, margin),
      Offset(size.width - margin, margin + cornerLength),
      paint,
    );

    // Bottom-right
    canvas.drawLine(
      Offset(size.width - margin, size.height - margin - cornerLength),
      Offset(size.width - margin, size.height - margin),
      paint,
    );
    canvas.drawLine(
      Offset(size.width - margin, size.height - margin),
      Offset(size.width - margin - cornerLength, size.height - margin),
      paint,
    );

    // Bottom-left
    canvas.drawLine(
      Offset(margin + cornerLength, size.height - margin),
      Offset(margin, size.height - margin),
      paint,
    );
    canvas.drawLine(
      Offset(margin, size.height - margin),
      Offset(margin, size.height - margin - cornerLength),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
