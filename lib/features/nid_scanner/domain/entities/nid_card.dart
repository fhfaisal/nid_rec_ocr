class NIDCard {
  final String? name;
  final String? nidNumber;
  final String? dateOfBirth;
  final String? fatherName;
  final String? motherName;
  // MRZ fields
  final String? gender;
  final String? expiryDate;
  final String? nationality;
  final String? surname;
  final String? givenNames;
  final String? address;

  final String rawText;
  final bool isNIDCard;

  NIDCard({
    this.name,
    this.nidNumber,
    this.dateOfBirth,
    this.fatherName,
    this.motherName,
    this.gender,
    this.expiryDate,
    this.nationality,
    this.surname,
    this.givenNames,
    this.address,
    required this.rawText,
    this.isNIDCard = false,
  });
}
