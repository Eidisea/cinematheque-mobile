import 'package:cloud_firestore/cloud_firestore.dart';

import 'model_utils.dart';

/// AVT and PDO have identical access. [position] is descriptive only.
enum StaffPosition { avt, pdo }

extension StaffPositionDb on StaffPosition {
  String get dbValue => switch (this) { StaffPosition.avt => 'AVT', StaffPosition.pdo => 'PDO' };
}

/// `staff/{uid}` — one document per Firebase Auth staff account (the doc ID is the Auth UID).
/// Customers never have a document here. Written only by the server or the Firebase console.
class StaffMember {
  const StaffMember({
    required this.uid,
    required this.firstName,
    this.middleName,
    required this.lastName,
    required this.email,
    required this.position,
    required this.isActive,
    this.createdAt,
  });

  final String uid;
  final String firstName;
  final String? middleName;
  final String lastName;
  final String email;
  final StaffPosition position;
  final bool isActive;
  final DateTime? createdAt;

  String get fullName => [firstName, middleName, lastName].whereType<String>().join(' ');

  factory StaffMember.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc, [SnapshotOptions? _]) =>
      StaffMember.fromMap(doc.id, doc.data() ?? const {});

  factory StaffMember.fromMap(String id, Map<String, dynamic> d) {
    return StaffMember(
      uid: id,
      firstName: requireString(d['firstName'], 'firstName'),
      middleName: stringOrNull(d['middleName']),
      lastName: requireString(d['lastName'], 'lastName'),
      email: requireString(d['email'], 'email'),
      position: enumFromDb(StaffPosition.values, (p) => p.dbValue, d['position'], 'position'),
      isActive: d['isActive'] == true,
      createdAt: dateOrNull(d['createdAt']),
    );
  }

  /// Staff documents are never written by the Flutter apps.
  static Map<String, Object?> toFirestore(StaffMember _, SetOptions? _) =>
      throw UnsupportedError('staff documents are written by the server only');
}
