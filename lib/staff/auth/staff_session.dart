import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../data/models/staff_member.dart';
import '../../data/repositories/firestore_collections.dart';

enum StaffSessionStatus {
  starting, // Firebase is restoring a previous login
  signedOut,
  verifying, // signed in to Firebase Auth, checking staff/{uid}
  signedIn, // confirmed ACTIVE staff member
}

class StaffSignInException implements Exception {
  const StaffSignInException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The staff member's login state. The router and screens listen to it.
///
/// Being signed in to Firebase Auth is not enough: the account must also have an
/// ACTIVE `staff/{uid}` document. The document is watched live, so a staff member
/// who is deactivated while working is signed out right away.
abstract class StaffSession extends ChangeNotifier {
  StaffSessionStatus get status;

  /// The signed-in staff member (only when [status] is signedIn).
  StaffMember? get staff;

  /// A message for the login screen, e.g. why someone was signed out.
  String? get notice;

  /// Throws [StaffSignInException] with a readable message on failure.
  Future<void> signIn({required String email, required String password});

  Future<void> signOut();
}

class FirebaseStaffSession extends StaffSession {
  FirebaseStaffSession({FirebaseAuth? auth, FirestoreCollections? collections})
      : _auth = auth ?? FirebaseAuth.instance,
        _collections = collections ?? FirestoreCollections(FirebaseFirestore.instance) {
    _authSub = _auth.authStateChanges().listen(_onAuthChanged);
  }

  final FirebaseAuth _auth;
  final FirestoreCollections _collections;
  late final StreamSubscription<User?> _authSub;
  StreamSubscription<DocumentSnapshot<StaffMember>>? _staffSub;

  StaffSessionStatus _status = StaffSessionStatus.starting;
  StaffMember? _staff;
  String? _notice;

  @override
  StaffSessionStatus get status => _status;

  @override
  StaffMember? get staff => _staff;

  @override
  String? get notice => _notice;

  void _set(StaffSessionStatus status, {StaffMember? staff}) {
    _status = status;
    _staff = staff;
    notifyListeners();
  }

  void _onAuthChanged(User? user) {
    _staffSub?.cancel();
    _staffSub = null;

    if (user == null) {
      _set(StaffSessionStatus.signedOut);
      return;
    }

    _set(StaffSessionStatus.verifying);
    _staffSub = _collections.staff.doc(user.uid).snapshots(includeMetadataChanges: true).listen(
      (doc) {
        // Decide only on the server's answer. A locally cached copy can be stale in both
        // directions (just reactivated, or just deactivated), so it is ignored.
        if (doc.metadata.isFromCache) return;
        StaffMember? member;
        try {
          member = doc.exists ? doc.data() : null;
        } on FormatException {
          _rejectAndSignOut('This staff record is incomplete. Ask an administrator to fix it.');
          return;
        }
        if (member == null) {
          _rejectAndSignOut('This account is not registered as Cinematheque staff.');
        } else if (!member.isActive) {
          _rejectAndSignOut('This staff account has been deactivated.');
        } else {
          _set(StaffSessionStatus.signedIn, staff: member);
        }
      },
      onError: (Object e) {
        debugPrint('Staff check failed: $e');
        _rejectAndSignOut('Could not verify staff access. Check your connection and try again.');
      },
    );
  }

  Future<void> _rejectAndSignOut(String message) async {
    _staffSub?.cancel();
    _staffSub = null;
    _notice = message;
    await _auth.signOut();
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    _notice = null;
    notifyListeners();
    try {
      await _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
    } on FirebaseAuthException catch (e) {
      throw StaffSignInException(_messageFor(e.code));
    }
  }

  @override
  Future<void> signOut() async {
    _notice = null;
    _staffSub?.cancel();
    _staffSub = null;
    await _auth.signOut();
  }

  static String _messageFor(String code) => switch (code) {
        'invalid-credential' || 'wrong-password' || 'user-not-found' || 'invalid-email' =>
          'Incorrect email or password.',
        'user-disabled' => 'This account has been disabled.',
        'too-many-requests' => 'Too many attempts. Please wait a few minutes and try again.',
        'network-request-failed' => 'No connection. Check your internet and try again.',
        _ => 'Sign-in failed ($code). Please try again.',
      };

  @override
  void dispose() {
    _authSub.cancel();
    _staffSub?.cancel();
    super.dispose();
  }
}
