import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../data/models/movie.dart';

/// An error answer from a staff route, e.g. code "not_approvable".
class StaffApiException implements Exception {
  const StaffApiException(this.code, {this.status, this.detail, this.fields = const {}});

  final String code;
  final int? status;
  final String? detail;

  /// Form errors per field ("email" → "Enter a valid email address.").
  final Map<String, String> fields;

  @override
  String toString() => 'StaffApiException($code${detail == null ? '' : ': $detail'})';
}

/// Staff actions that only the server may carry out (it holds the Admin SDK and the
/// email/PayMongo secrets). Each call carries the staff member's Firebase ID token.
abstract class StaffApi {
  Future<void> approve(String reservationId);

  /// → how many were approved.
  Future<int> approveAll(String screeningId);

  Future<void> cancel(String reservationId);

  /// → "sent", "failed" or "not_configured".
  Future<String> resendEmail(String reservationId);

  /// Uploads a poster image to Cloudinary (signed by the server) → where it now lives.
  Future<Poster> uploadPoster(Uint8List bytes, String filename);

  /// Removes a poster that is no longer used (best effort).
  Future<void> deletePoster(String publicId);

  /// Creates a staff account (sign-in + staff record) → its uid.
  Future<String> createStaff(StaffAccountForm form);

  /// Saves details; a blank password keeps the current one.
  Future<void> updateStaff(String uid, StaffAccountForm form);

  Future<void> setStaffActive(String uid, bool active);
}

/// What the staff account form sends.
class StaffAccountForm {
  const StaffAccountForm({
    required this.firstName,
    this.middleName,
    required this.lastName,
    required this.email,
    required this.position,
    this.password,
  });

  final String firstName;
  final String? middleName;
  final String lastName;
  final String email;
  final String position; // AVT or PDO
  final String? password;

  Map<String, Object?> toJson() => {
        'firstName': firstName,
        'middleName': middleName,
        'lastName': lastName,
        'email': email,
        'position': position,
        'password': password ?? '',
      };
}

class HttpStaffApi implements StaffApi {
  HttpStaffApi(this.baseUrl, {required this.idToken, http.Client? client}) : _client = client ?? http.Client();

  final String baseUrl;
  final Future<String?> Function() idToken;
  final http.Client _client;

  static const _timeout = Duration(seconds: 20);

  Future<Map<String, dynamic>> _post(Map<String, Object?> body, {String path = '/api/staff/reservations'}) async {
    final token = await idToken();
    if (token == null) throw const StaffApiException('unauthenticated');
    final http.Response res;
    try {
      res = await _client
          .post(
            Uri.parse('$baseUrl$path'),
            headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);
    } catch (_) {
      throw const StaffApiException('network');
    }
    Map<String, dynamic> json;
    try {
      json = (jsonDecode(res.body) as Map).cast<String, dynamic>();
    } catch (_) {
      throw StaffApiException('server_error', status: res.statusCode);
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return json;
    throw StaffApiException(
      json['error'] as String? ?? 'server_error',
      status: res.statusCode,
      detail: json['detail'] as String?,
      fields: {for (final e in ((json['fields'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'},
    );
  }

  @override
  Future<void> approve(String reservationId) => _post({'action': 'approve', 'reservationId': reservationId});

  @override
  Future<int> approveAll(String screeningId) async =>
      ((await _post({'action': 'approveAll', 'screeningId': screeningId}))['approved'] as num?)?.toInt() ?? 0;

  @override
  Future<void> cancel(String reservationId) => _post({'action': 'cancel', 'reservationId': reservationId});

  @override
  Future<String> resendEmail(String reservationId) async =>
      (await _post({'action': 'resend', 'reservationId': reservationId}))['email'] as String? ?? 'failed';

  @override
  Future<Poster> uploadPoster(Uint8List bytes, String filename) async {
    final ticket = await _post({'action': 'sign'}, path: '/api/staff/poster');
    final request = http.MultipartRequest('POST', Uri.parse(ticket['uploadUrl'] as String))
      ..fields.addAll({
        'api_key': '${ticket['apiKey']}',
        'timestamp': '${ticket['timestamp']}',
        'folder': '${ticket['folder']}',
        'allowed_formats': '${ticket['allowed_formats']}',
        'signature': '${ticket['signature']}',
      })
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final http.Response res;
    try {
      res = await http.Response.fromStream(await _client.send(request).timeout(const Duration(seconds: 60)));
    } catch (_) {
      throw const StaffApiException('network');
    }
    Map<String, dynamic> json;
    try {
      json = (jsonDecode(res.body) as Map).cast<String, dynamic>();
    } catch (_) {
      throw StaffApiException('upload_failed', status: res.statusCode);
    }
    final url = json['secure_url'], publicId = json['public_id'];
    if (res.statusCode != 200 || url is! String || publicId is! String) {
      throw StaffApiException('upload_failed', status: res.statusCode, detail: (json['error'] as Map?)?['message'] as String?);
    }
    return Poster(url: url, publicId: publicId);
  }

  @override
  Future<void> deletePoster(String publicId) => _post({'action': 'delete', 'publicId': publicId}, path: '/api/staff/poster');

  static const _accounts = '/api/staff/accounts';

  @override
  Future<String> createStaff(StaffAccountForm form) async =>
      (await _post({'action': 'create', ...form.toJson()}, path: _accounts))['uid'] as String;

  @override
  Future<void> updateStaff(String uid, StaffAccountForm form) =>
      _post({'action': 'update', 'uid': uid, ...form.toJson()}, path: _accounts);

  @override
  Future<void> setStaffActive(String uid, bool active) =>
      _post({'action': active ? 'activate' : 'deactivate', 'uid': uid}, path: _accounts);
}

/// A readable message for a failed staff action.
String staffApiMessage(Object error) {
  if (error is! StaffApiException) return 'Something went wrong. Please try again.';
  return switch (error.code) {
    'network' => 'No connection to the server. Please try again.',
    'unauthenticated' || 'not_staff' => 'Your staff session has ended. Please sign in again.',
    'not_approvable' => 'This booking can no longer be approved (${error.detail ?? 'it changed'}).',
    'not_cancellable' => 'This booking can no longer be cancelled (${error.detail ?? 'it changed'}).',
    'not_found' => 'This booking no longer exists.',
    'upload_failed' => 'The poster could not be uploaded${error.detail == null ? '' : ' (${error.detail})'}. Use a JPG, PNG or WebP image.',
    'not_configured' => 'Poster uploads are not set up on the server.',
    'validation' || 'email_exists' => 'Please fix the highlighted fields.',
    'self' => 'You can’t deactivate your own account.',
    _ => 'The server could not do that. Please try again.',
  };
}
