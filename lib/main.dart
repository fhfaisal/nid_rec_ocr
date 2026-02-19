import 'dart:developer';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import 'camera_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NID Card Scanner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const TextRecognitionPage(),
    );
  }
}

// Model class for NID Card data
class NIDCardData {
  final String? name;
  final String? nidNumber;
  final String? dateOfBirth;
  final String? fatherName;
  final String? motherName;
  final String rawText;
  final bool isNIDCard;

  NIDCardData({
    this.name,
    this.nidNumber,
    this.dateOfBirth,
    this.fatherName,
    this.motherName,
    required this.rawText,
    this.isNIDCard = false,
  });
}

class TextRecognitionPage extends StatefulWidget {
  const TextRecognitionPage({super.key});

  @override
  State<TextRecognitionPage> createState() => _TextRecognitionPageState();
}

class _TextRecognitionPageState extends State<TextRecognitionPage> {
  File? _image;
  NIDCardData? _nidData;
  bool _isProcessing = false;
  final ImagePicker _picker = ImagePicker();
  final TextRecognizer _latinRecognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );
  final TextRecognizer _devanagariRecognizer = TextRecognizer(
    script: TextRecognitionScript.devanagiri,
  );

  Future<void> _pickImage(ImageSource source) async {
    try {
      String? imagePath;

      if (source == ImageSource.camera) {
        // Show instruction screen, then open camera
        imagePath = await Navigator.push<String>(
          context,
          MaterialPageRoute(
            builder: (context) => const CameraInstructionScreen(),
          ),
        );
      } else {
        // Use image picker for gallery
        final XFile? pickedFile = await _picker.pickImage(source: source);
        imagePath = pickedFile?.path;
      }

      if (imagePath != null) {
        setState(() {
          _image = File(imagePath!);
          _nidData = null;
          _isProcessing = true;
        });

        await _recognizeText(imagePath);
      }
    } catch (e) {
      _showError('Error picking image: $e');
    }
  }
  String _removeDuplicateLines(String text) {
    final seen = <String>{};
    final buffer = StringBuffer();

    for (final line in text.split('\n')) {
      final clean = line.trim();
      if (clean.isNotEmpty && !seen.contains(clean)) {
        seen.add(clean);
        buffer.writeln(clean);
      }
    }
    return buffer.toString();
  }

  String _normalizeOCR(String text) {
    return _removeDuplicateLines(text)
        .replaceAll(';', ':')
        .replaceAll('।', ':')
        .replaceAll('|', 'I')

    // ID → NID normalization
        .replaceAll(RegExp(r'\bID\s*NO\b', caseSensitive: false), 'NID NO')
        .replaceAll(RegExp(r'\bI0\s*NO\b', caseSensitive: false), 'NID NO')
        .replaceAll(RegExp(r'\bD\s*NO\b', caseSensitive: false), 'NID NO')

    // Bengali label normalization
        .replaceAll(RegExp(r'পিভা|পিতা\s*;'), 'পিতা:')
        .replaceAll(RegExp(r'মতা|মাতা\s*;'), 'মাতা:')

    // remove garbage
        .replaceAll(RegExp(r'[^\x00-\x7F\u0980-\u09FF:\n ]'), '')
        .replaceAll(RegExp(r'[ ]{2,}'), ' ')
        .trim();
  }


  Future<void> _recognizeText(String imagePath) async {
    try {
      final inputImage = InputImage.fromFilePath(imagePath);

      final results = await Future.wait([
        _latinRecognizer.processImage(inputImage),
        _devanagariRecognizer.processImage(inputImage),
      ]);

      final latinText = results[0].text;
      final bengaliText = results[1].text;

      final String combinedText = '$bengaliText\n$latinText';

      // ⭐ NEW → normalize before parsing
      final normalized = _normalizeOCR(combinedText);

      log(normalized);

      final nidData = _parseNIDCard(normalized);

      setState(() {
        _nidData = nidData;
        _isProcessing = false;
      });

      if (normalized.trim().isEmpty) {
        _showError('No text found in the image');
      } else if (!nidData.isNIDCard) {
        _showMessage('Note: This may not be a Bangladesh NID card', isWarning: true);
      }
    } catch (e) {
      setState(() => _isProcessing = false);
      _showError('Error recognizing text: $e');
    }
  }


  NIDCardData _parseNIDCard(String text) {
    log(text);
    // Check if it's likely a Bangladesh NID card
    final isNID = text.contains('National ID Card') ||
        text.contains('NID') ||
        text.contains('Bangladesh') ||
        text.contains('বাংলাদেশ') ||
        text.contains('জাতীয় পরিচয়পত্র');

    String? name;
    String? nidNumber;
    String? dateOfBirth;
    String? fatherName;
    String? motherName;

    // Extract Name (English)
    // Use positive lookahead to stop at common keywords or newline
    // Case 1: "Name: VALUE"
    // Case 2: "Name\nVALUE"
    // Typo handling: "Narme", "Nam"
    // 1. Updated Name Regex to handle slashes "/" and non-word noise from OCR
    // 1. Added "-" to the character set to allow names like AL-AMIN
    final nameRegex = RegExp(
        r'(?:Name|Narme|Nam)[^a-zA-Z]*([A-Z\s.\-]+)',
        caseSensitive: false,
        multiLine: true
    );

    final nameMatch = nameRegex.firstMatch(text);
    if (nameMatch != null) {
      // Extract the raw match
      String rawName = nameMatch.group(1) ?? "";

      // 2. Clean up leading non-alphabet noise (like "/ " or "- ")
      // but we only want to strip them if they are at the very START
      name = rawName.replaceFirst(RegExp(r'^[^a-zA-Z]+'), '').trim();

      // 3. Prevent overflow into "Date of Birth"
      // Since we are now more aggressive, we must ensure we don't swallow the next field
      if (name.toLowerCase().contains("date")) {
        name = name.split(RegExp(r'date', caseSensitive: false))[0].trim();
      }
    }

    // Alternative: Look for pattern "MD. [NAME]" or similar if name not found
    if (name == null || name.isEmpty) {
      final mdPattern = RegExp(r'(MD\.|MR\.|MRS\.|MS\.)\s*([A-Z\s]+)', caseSensitive: false);
      final mdMatch = mdPattern.firstMatch(text);
      if (mdMatch != null) {
        name = '${mdMatch.group(1)} ${mdMatch.group(2)}'.trim();
      }
    }

    // Extract NID Number (10, 13, or 17 digits, allowing spaces)
    // Look for "NID No" followed by digits (with potential spaces)
    final nidRegex = RegExp(r'NID\s*No[:\s]*([\d\s]{10,25})', caseSensitive: false);
    var nidMatch = nidRegex.firstMatch(text);

    if (nidMatch != null) {
      String rawNid = nidMatch.group(1) ?? "";
      String cleanedNid = rawNid.replaceAll(RegExp(r'\s+'), '');
      if (cleanedNid.length == 10 || cleanedNid.length == 13 || cleanedNid.length == 17) {
        nidNumber = rawNid.trim(); // Keep original spacing or use cleanedNid based on preference
      }
    }

    // Fallback: finding any valid NID-like number sequence if "NID No" label is missing/unreadable
    if (nidNumber == null) {
      // Look for standalone number sequences that match NID length
      // 3 groups of digits implies the formatting like 286 133 2134
      // We use [ ] instead of \s to avoid matching newlines which might merge Date of Birth year
      final digitRegex = RegExp(r'\b(\d{3,4}[ ]?\d{3,4}[ ]?\d{3,4}(?:[ ]\d{1,4})?)\b');
      final allMatches = digitRegex.allMatches(text);

      for (final match in allMatches) {
        String possibleNid = match.group(0) ?? "";
        String cleaned = possibleNid.replaceAll(RegExp(r'[\s-]'), '');
        // National IDs are usually 10, 13, or 17 digits
        if (cleaned.length == 10 || cleaned.length == 13 || cleaned.length == 17) {
          nidNumber = possibleNid.trim();
          break; // Assume first valid match is the NID
        }
      }
    }

    // Extract Date of Birth
    final dobRegex = RegExp(r'Date\s*of\s*Birth[:\s]*(\d{1,2}\s*(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s*\d{4})',
        caseSensitive: false);
    var dobMatch = dobRegex.firstMatch(text);

    if (dobMatch != null) {
      dateOfBirth = dobMatch.group(1);
    } else {
      // Try alternative formats
      final dobAltRegex = RegExp(r'(\d{1,2}[-/]\d{1,2}[-/]\d{4})');
      dobMatch = dobAltRegex.firstMatch(text);
      if (dobMatch != null) {
        dateOfBirth = dobMatch.group(1);
      }
    }

    // Extract Father's Name (in Bengali text pattern)
    final fatherRegex = RegExp(r'(?:পিতা|পিভা)[:\s]*(.+?)(?=মাতা|Date|NID|\n|$)', multiLine: true);
    final fatherMatch = fatherRegex.firstMatch(text);
    if (fatherMatch != null) {
      fatherName = fatherMatch.group(1)?.trim();
    }

    // Extract Mother's Name (in Bengali text pattern)
    final motherRegex = RegExp(r'(?:মাতা|আতা|মতা)[:\s]*(.+?)(?=Date|NID|\n|$)', multiLine: true);
    final motherMatch = motherRegex.firstMatch(text);
    if (motherMatch != null) {
      motherName = motherMatch.group(1)?.trim();
    }

    return NIDCardData(
      name: name,
      nidNumber: nidNumber,
      dateOfBirth: dateOfBirth,
      fatherName: fatherName,
      motherName: motherName,
      rawText: text,
      isNIDCard: isNID,
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

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showMessage(String message, {bool isWarning = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isWarning ? Colors.orange : Colors.blue,
      ),
    );
  }

  void _showImageSourceDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select Image Source'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Camera'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _latinRecognizer.close();
    _devanagariRecognizer.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NID Scanner'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (_nidData != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                setState(() {
                  _image = null;
                  _nidData = null;
                });
              },
              tooltip: 'Clear',
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Image Display Section
              Container(
                height: 250,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[400]!),
                ),
                child: _image != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          _image!,
                          fit: BoxFit.contain,
                        ),
                      )
                    : Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.credit_card,
                              size: 80,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No NID card scanned',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
              const SizedBox(height: 20),

              // Pick Image Button
              ElevatedButton.icon(
                onPressed: _showImageSourceDialog,
                icon: const Icon(Icons.camera_alt),
                label: const Text('Scan NID Card'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Processing Indicator or Card Details
              if (_isProcessing)
                const Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Scanning NID card...'),
                    ],
                  ),
                )
              else if (_nidData != null)
                _buildNIDCardInfo()
              else
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 60,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Tap "Scan NID Card" to get started',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'This app will automatically detect and extract information from Bangladesh National ID cards',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNIDCardInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Card Detection Status
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _nidData!.isNIDCard ? Colors.green[50] : Colors.orange[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _nidData!.isNIDCard ? Colors.green : Colors.orange,
            ),
          ),
          child: Row(
            children: [
              Icon(
                _nidData!.isNIDCard ? Icons.check_circle : Icons.warning,
                color: _nidData!.isNIDCard ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _nidData!.isNIDCard ? 'NID Card Detected' : 'May not be a valid NID card',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _nidData!.isNIDCard ? Colors.green[900] : Colors.orange[900],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Extracted Information
        const Text(
          'Extracted Information:',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),

        // Name
        if (_nidData!.name != null)
          _buildInfoCard(
            icon: Icons.person,
            label: 'Name',
            value: _nidData!.name!,
          ),

        // NID Number
        if (_nidData!.nidNumber != null)
          _buildInfoCard(
            icon: Icons.badge,
            label: 'NID Number',
            value: _nidData!.nidNumber!,
          ),

        // Date of Birth
        if (_nidData!.dateOfBirth != null)
          _buildInfoCard(
            icon: Icons.cake,
            label: 'Date of Birth',
            value: _nidData!.dateOfBirth!,
          ),

        // Father's Name
        if (_nidData!.fatherName != null)
          _buildInfoCard(
            icon: Icons.family_restroom,
            label: "Father's Name",
            value: _nidData!.fatherName!,
          ),

        // Mother's Name
        if (_nidData!.motherName != null)
          _buildInfoCard(
            icon: Icons.family_restroom,
            label: "Mother's Name",
            value: _nidData!.motherName!,
          ),

        const SizedBox(height: 20),

        // Raw Text Expander
        ExpansionTile(
          title: const Text(
            'Raw Recognized Text',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.grey[100],
              child: SelectableText(
                _nidData!.rawText,
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.green[700], size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 20),
            onPressed: () => _copyToClipboard(value, label),
            tooltip: 'Copy',
            color: Colors.grey[600],
          ),
        ],
      ),
    );
  }
}
