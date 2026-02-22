import 'dart:developer';
import 'dart:io';
import 'package:string_similarity/string_similarity.dart';
import '../entities/nid_card.dart';
import '../repositories/ocr_repository.dart';

class ScanNIDUseCase {
  final OCRRepository repository;

  ScanNIDUseCase(this.repository);

  Future<NIDCard> execute(File image) async {
    final rawText = await repository.recognizeText(image);
    log('Raw Recognized Text: $rawText');
    final normalized = _normalizeOCR(rawText);
    return _parseNIDCard(normalized);
  }

  String _normalizeOCR(String text) {
    return _removeDuplicateLines(text)
        .replaceAll(';', ':')
        .replaceAll('।', ':')
        .replaceAll('|', 'I')
        .replaceAll(RegExp(r'[^\x00-\x7F\u0980-\u09FF:\n ]'), '')
        .replaceAll(RegExp(r'[ ]{2,}'), ' ')
        .trim();
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

  NIDCard _parseNIDCard(String text) {
    final isNID = text.contains('National ID Card') ||
        text.contains('NID') ||
        text.contains('Bangladesh') ||
        text.contains('বাংলাদেশ') ||
        text.contains('জাতীয় পরিচয়পত্র');

    final lines = text.split('\n').where((l) => l.trim().isNotEmpty).toList();

    String? name = _findBestValue(lines, ['Name', 'Name English', 'Nam']);
    String? nidNumber = _findBestValue(lines, ['NID No', 'ID NO', 'NID Number', 'No:']);
    String? dateOfBirth = _findBestValue(lines, ['Date of Birth', 'Birth', 'Birthday']);
    String? fatherName = _findBestValue(lines, ['পিতা','পিভা', 'Father', 'Father Name']);
    String? motherName = _findBestValue(lines, ['মাতা','মতা','আতা','অতা', 'Mother', 'Mother Name']);

    // Fallbacks and extra cleaning
    if (name != null) {
      name = name.replaceFirst(RegExp(r'^[^a-zA-Z]+'), '').trim();
      if (name.toLowerCase().contains("date")) {
        name = name.split(RegExp(r'date', caseSensitive: false))[0].trim();
      }
    }

    if (name == null || name.isEmpty) {
      final mdPattern = RegExp(r'(MD\.|MR\.|MRS\.|MS\.)\s*([A-Z\s]+)', caseSensitive: false);
      final mdMatch = mdPattern.firstMatch(text);
      if (mdMatch != null) {
        name = '${mdMatch.group(1)} ${mdMatch.group(2)}'.trim();
      }
    }

    if (nidNumber != null) {
      nidNumber = _normalizeDigits(nidNumber);
      String cleanedNid = nidNumber.replaceAll(RegExp(r'\s+'), '');
      if (cleanedNid.length != 10 && cleanedNid.length != 13 && cleanedNid.length != 17) {
        nidNumber = null;
      }
    }

    if (nidNumber == null) {
      final digitRegex = RegExp(r'\b(\d{3,4}[ ]?\d{3,4}[ ]?\d{3,4}(?:[ ]\d{1,4})?)\b');
      final allMatches = digitRegex.allMatches(_normalizeDigits(text));
      for (final match in allMatches) {
        String possibleNid = match.group(0) ?? "";
        String cleaned = possibleNid.replaceAll(RegExp(r'[\s-]'), '');
        if (cleaned.length == 10 || cleaned.length == 13 || cleaned.length == 17) {
          nidNumber = possibleNid.trim();
          break;
        }
      }
    }

    if (dateOfBirth != null) {
      dateOfBirth = _normalizeDigits(dateOfBirth);
    }

    return NIDCard(
      name: name,
      nidNumber: nidNumber,
      dateOfBirth: dateOfBirth,
      fatherName: fatherName,
      motherName: motherName,
      rawText: text,
      isNIDCard: isNID,
    );
  }

  String _normalizeDigits(String input) {
    const bengaliToEnglish = {
      '০': '0', '১': '1', '২': '2', '৩': '3', '৪': '4',
      '৫': '5', '৬': '6', '৭': '7', '৮': '8', '৯': '9',
      'O': '0', 'o': '0',
    };

    String output = input;
    bengaliToEnglish.forEach((b, e) {
      output = output.replaceAll(b, e);
    });
    return output;
  }

  String? _findBestValue(List<String> lines, List<String> labels) {
    int bestLineIndex = -1;
    double highestScore = 0.0;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim().toLowerCase();
      for (final label in labels) {
        final lowerLabel = label.toLowerCase();

        double score = line.similarityTo(lowerLabel);
        if (line == lowerLabel || line == '$lowerLabel:') {
          score = 1.0;
        } else if (line.contains(lowerLabel)) {
          score += 0.4;
        }

        // FIX 2: On very high confidence, take the FIRST match and stop searching.
        // This prevents duplicate card blocks from overriding the first correct result.
        if (score >= 0.9) {
          bestLineIndex = i;
          highestScore = score;
          break; // stop checking labels for this line
        }

        if (score > highestScore && score > 0.45) {
          highestScore = score;
          bestLineIndex = i;
        }
      }

      // FIX 2 (continued): Also break outer loop if we have a near-perfect match
      if (highestScore >= 0.9) break;
    }

    if (bestLineIndex != -1) {
      final targetLine = lines[bestLineIndex];

      // FIX 1: Try to extract value from the SAME line first, after the label text.
      // This fixes cases like "Date of Birth 25 Dec 2000" where the value is inline.
      for (final label in labels) {
        final pattern = RegExp(
          '${RegExp.escape(label)}[:\\s]+(.+)',
          caseSensitive: false,
        );
        final inlineMatch = pattern.firstMatch(targetLine);
        if (inlineMatch != null) {
          final inlineValue = inlineMatch.group(1)!.trim();
          if (inlineValue.isNotEmpty) {
            return inlineValue;
          }
        }
      }

      // Try same line after colon
      final parts = targetLine.split(':');
      if (parts.length > 1 && parts[1].trim().isNotEmpty) {
        return parts[1].trim();
      }

      // Try next line
      if (bestLineIndex + 1 < lines.length) {
        final nextLine = lines[bestLineIndex + 1].trim();
        if (nextLine.isNotEmpty && !_isPotentialLabel(nextLine)) {
          return nextLine;
        }
      }

      // Try PREVIOUS line (special case: value above label)
      if (bestLineIndex - 1 >= 0) {
        final prevLine = lines[bestLineIndex - 1].trim();
        if (prevLine.isNotEmpty && !_isPotentialLabel(prevLine) && prevLine.length > 2) {
          return prevLine;
        }
      }

      // Fallback: same line after label name
      for (final label in labels) {
        final lowerLabel = label.toLowerCase();
        if (targetLine.toLowerCase().contains(lowerLabel)) {
          final index = targetLine.toLowerCase().indexOf(lowerLabel);
          final remaining = targetLine.substring(index + label.length).trim();
          final cleaned = remaining.replaceFirst(RegExp(r'^[:.\s/]+'), '').trim();
          if (cleaned.isNotEmpty) return cleaned;
        }
      }
    }
    return null;
  }

  bool _isPotentialLabel(String line) {
    final lowerLine = line.toLowerCase();
    final commonLabels = [
      'name',
      'nid',
      'date',
      'birth',
      'পিতা',
      'মাতা',
      'father',
      'mother',
      'জাতীয়',
      'পরিচয়',
      'government',
      'republic',
      // FIX 3: catch garbled OCR noise like "হথা ND No"
      'no',
      'id',
      'nd',
      'হথা',
      'card',
    ];
    // Don't treat long lines as labels
    if (line.length > 30) return false;
    return commonLabels.any((label) => lowerLine.contains(label));
  }

  Future<NIDCard> executeBackSide(File image) async {
    final rawText = await repository.recognizeText(image);
    log('Back Side Raw Recognized Text: $rawText');
    return _parseMRZ(rawText);
  }

  NIDCard _parseMRZ(String text) {
    final rawLines = text.split('\n').map((l) => l.trim()).toList();

    // 1. Extract Address
    List<String> addressParts = [];
    bool foundAddressHeader = false;
    final addressLabels = ['ঠিকানা', 'বাসা', 'গ্রাম', 'ডাকঘর', 'রাস্তা', 'hold', 'village', 'post'];

    for (int i = 0; i < rawLines.length; i++) {
      final line = rawLines[i];
      final lowerLine = line.toLowerCase();

      bool isAddressLabel = addressLabels.any((label) {
        if (lowerLine.contains(label)) return true;
        for (var part in lowerLine.split(RegExp(r'[:.\s]'))) {
          if (part.length > 3 && part.similarityTo(label) > 0.6) return true;
        }
        return false;
      });

      if (isAddressLabel) {
        addressParts.add(line);
        foundAddressHeader = true;
      } else if (foundAddressHeader) {
        if (line.contains('<') ||
            line.toLowerCase().contains('birth') ||
            line.toLowerCase().contains('date')) {
          break;
        }
        if (line.length > 5 && addressParts.length < 5) {
          addressParts.add(line);
        }
      }
    }
    String? address = addressParts.isNotEmpty ? addressParts.join('\n') : null;

    // 2. Extract MRZ Lines
    final mrzLines = rawLines.map((l) => l.replaceAll(' ', '')).toList();
    String? line1, line2, line3;

    for (int i = 0; i < mrzLines.length; i++) {
      final line = mrzLines[i];
      if (line.startsWith('I<BGD') || (line.startsWith('I<') && line.contains('BGD'))) {
        line1 = line;
        if (i + 1 < mrzLines.length) line2 = mrzLines[i + 1];
        if (i + 2 < mrzLines.length) line3 = mrzLines[i + 2];
        break;
      }
    }

    String? nidNumber, dob, gender, expiry, nationality, surname, givenNames;

    if (line1 != null && line2 != null && line3 != null) {
      final cleanLine1 = _normalizeDigits(line1);
      final cleanLine2 = _normalizeDigits(line2);
      final cleanLine3 = line3;

      final match = RegExp(r'BGD([A-Z0-9]+)<').firstMatch(cleanLine1);
      nidNumber = match?.group(1);

      if (cleanLine2.length >= 18) {
        String rawDob = cleanLine2.substring(0, 6);
        dob = _formatMRZDate(rawDob, isExpiry: false);
        final genderChar = cleanLine2.substring(7, 8).toUpperCase();
        gender = genderChar == 'M' ? 'Male' : (genderChar == 'F' ? 'Female' : 'Others');
        String rawExpiry = cleanLine2.substring(8, 14);
        expiry = _formatMRZDate(rawExpiry, isExpiry: true);
        nationality = cleanLine2.substring(15, 18);
      }

      final names = cleanLine3.split('<<');
      if (names.isNotEmpty) {
        surname = names[0].replaceAll('<', ' ').trim();
        if (names.length > 1) {
          givenNames = names[1].replaceAll('<', ' ').trim();
        }
      }
    }

    String? fullName;
    if (givenNames != null && surname != null) {
      fullName = '$givenNames $surname'.replaceAll(RegExp(r'\s+'), ' ');
    } else {
      fullName = givenNames ?? surname;
    }

    return NIDCard(
      nidNumber: nidNumber,
      dateOfBirth: dob,
      gender: gender,
      expiryDate: expiry,
      nationality: nationality,
      surname: surname,
      givenNames: givenNames,
      address: address,
      name: fullName,
      rawText: text,
      isNIDCard: true,
    );
  }

  String _formatMRZDate(String raw, {bool isExpiry = false}) {
    if (raw.length != 6) return raw;
    String yy = raw.substring(0, 2);
    String mm = raw.substring(2, 4);
    String dd = raw.substring(4, 6);

    int? year = int.tryParse(yy);
    int? month = int.tryParse(mm);
    int? day = int.tryParse(dd);

    if (year == null || month == null || day == null) return raw;

    int currentYearLastTwo = DateTime.now().year % 100;
    String fullYear;

    if (isExpiry) {
      fullYear = '20$yy';
    } else {
      fullYear = year > currentYearLastTwo ? '19$yy' : '20$yy';
    }

    return '$dd/$mm/$fullYear';
  }
}