import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../../data/datasources/image_processor.dart';

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isTakingPicture = false;
  String? _errorMessage;
  final ImageProcessor _imageProcessor = ImageProcessor();

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
    if (_controller == null || !_controller!.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        setState(() => _errorMessage = 'No camera found');
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
      setState(() {
        _errorMessage = 'Camera unavailable';
        _isInitialized = false;
      });
    }
  }

  Future<void> _takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized || _isTakingPicture) return;

    try {
      final Size screenSize = MediaQuery.of(context).size;
      final double viewportWidth = screenSize.width - 48;
      const double viewportHeight = 240.0;

      setState(() => _isTakingPicture = true);

      final XFile picture = await _controller!.takePicture();
      final File imageFile = File(picture.path);

      final croppedFile = await _imageProcessor.cropImage(
        imageFile,
        viewportWidth,
        viewportHeight,
      );

      if (mounted) {
        Navigator.of(context).pop(croppedFile?.path ?? picture.path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isTakingPicture = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildBody()),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
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
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCameraPreviewContainer(),
          const SizedBox(height: 24),
          if (_isInitialized) _buildStatusIndicator(),
          const SizedBox(height: 24),
          _buildInstructions(),
        ],
      ),
    );
  }

  Widget _buildCameraPreviewContainer() {
    return Container(
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
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;

  Widget _buildCameraPreview() {
    if (_errorMessage != null) {
      return Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.orange)));
    }
    if (!_isInitialized || _controller == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.green));
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _controller!.value.previewSize!.height,
            height: _controller!.value.previewSize!.width,
            child: CameraPreview(_controller!),
          ),
        ),
        CustomPaint(painter: CardFramePainter()),
        const Positioned(
          bottom: 16,
          left: 16,
          right: 16,
          child: Text(
            'Position NID card to fill the frame',
            style: TextStyle(color: Colors.white, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        const Text('Camera Ready', style: TextStyle(color: Colors.green, fontSize: 14)),
      ],
    );
  }

  Widget _buildInstructions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Photography Tips', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        _buildTipItem(Icons.wb_sunny_outlined, 'Good Lighting', 'Ensure the card is well-lit with no shadows'),
        _buildTipItem(Icons.crop_free, 'Full Card Visible', 'Capture the entire card within the frame'),
        _buildTipItem(Icons.straighten, 'Keep Level', 'Hold your phone parallel to the card'),
      ],
    );
  }

  Widget _buildTipItem(IconData icon, String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(icon, color: Colors.green[300], size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                Text(description, style: TextStyle(color: Colors.grey[400], fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _isInitialized && !_isTakingPicture ? _takePicture : null,
          icon: _isTakingPicture
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.camera, size: 24),
          label: Text(_isTakingPicture ? 'Capturing...' : 'Capture Photo',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
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

    const cornerLength = 30.0;
    const margin = 20.0;

    // Top-left
    canvas.drawLine(const Offset(margin, margin + cornerLength), const Offset(margin, margin), paint);
    canvas.drawLine(const Offset(margin, margin), const Offset(margin + cornerLength, margin), paint);
    // Top-right
    canvas.drawLine(Offset(size.width - margin - cornerLength, margin), Offset(size.width - margin, margin), paint);
    canvas.drawLine(Offset(size.width - margin, margin), Offset(size.width - margin, margin + cornerLength), paint);
    // Bottom-right
    canvas.drawLine(Offset(size.width - margin, size.height - margin - cornerLength),
        Offset(size.width - margin, size.height - margin), paint);
    canvas.drawLine(Offset(size.width - margin, size.height - margin),
        Offset(size.width - margin - cornerLength, size.height - margin), paint);
    // Bottom-left
    canvas.drawLine(Offset(margin + cornerLength, size.height - margin), Offset(margin, size.height - margin), paint);
    canvas.drawLine(Offset(margin, size.height - margin), Offset(margin, size.height - margin - cornerLength), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
