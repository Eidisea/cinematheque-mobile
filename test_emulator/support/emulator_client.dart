import 'dart:convert';

import 'package:http/http.dart' as http;

/// Minimal client for the LOCAL Firestore emulator's REST API, used only by the
/// security-rules tests. It never talks to the real Firebase project: the emulator
/// runs with the fake project ID `demo-ccd` (the "demo-" prefix guarantees that).
///
/// Each client acts as one identity:
///   EmulatorClient.guest()          → no login (a customer)
///   EmulatorClient.user('uid')      → a signed-in Firebase Auth user
///   EmulatorClient.admin()          → bypasses the rules (like the Vercel server), for test setup
///
/// Methods return the HTTP status: 200 = allowed, 403 = denied by the rules.
class EmulatorClient {
  EmulatorClient._(this._authorization);

  factory EmulatorClient.guest() => EmulatorClient._(null);
  factory EmulatorClient.admin() => EmulatorClient._('Bearer owner');
  factory EmulatorClient.user(String uid) => EmulatorClient._('Bearer ${_unsignedIdToken(uid)}');

  static const projectId = 'demo-ccd';
  static const _host = 'http://127.0.0.1:8080';
  static const _dbPath = 'projects/$projectId/databases/(default)/documents';

  final String? _authorization;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_authorization != null) 'Authorization': _authorization,
      };

  /// Deletes every document in the emulator.
  static Future<void> clearAll() async {
    final res = await http.delete(Uri.parse('$_host/emulator/v1/$_dbPath'));
    if (res.statusCode != 200) throw StateError('Could not clear emulator: ${res.statusCode} ${res.body}');
  }

  Future<int> get(String path) async =>
      (await http.get(Uri.parse('$_host/v1/$_dbPath/$path'), headers: _headers)).statusCode;

  /// Lists (queries) a collection — the operation `allow list` controls.
  Future<int> list(String collectionId) async {
    final res = await http.post(
      Uri.parse('$_host/v1/$_dbPath:runQuery'),
      headers: _headers,
      body: jsonEncode({
        'structuredQuery': {
          'from': [
            {'collectionId': collectionId},
          ],
          'limit': 5,
        },
      }),
    );
    return res.statusCode;
  }

  /// Creates a NEW document (fails if it already exists).
  Future<int> create(String path, Map<String, Object?> data) => _commit(path, data, mustNotExist: true);

  /// Creates or fully replaces a document (like `set()`).
  Future<int> set(String path, Map<String, Object?> data) => _commit(path, data);

  /// Changes only the given fields (like `update()`).
  Future<int> update(String path, Map<String, Object?> fields) => _commit(path, fields, onlyTheseFields: true);

  Future<int> delete(String path) async => (await http.post(
        Uri.parse('$_host/v1/$_dbPath:commit'),
        headers: _headers,
        body: jsonEncode({
          'writes': [
            {'delete': '$_dbPath/$path'},
          ],
        }),
      ))
          .statusCode;

  Future<int> _commit(String path, Map<String, Object?> data,
      {bool mustNotExist = false, bool onlyTheseFields = false}) async {
    final fields = <String, Object?>{};
    final serverTimeFields = <String>[];
    data.forEach((key, value) => value is ServerTime ? serverTimeFields.add(key) : fields[key] = value);

    final write = <String, Object?>{
      'update': {'name': '$_dbPath/$path', 'fields': _encodeFields(fields)},
      if (onlyTheseFields) 'updateMask': {'fieldPaths': fields.keys.toList()},
      if (serverTimeFields.isNotEmpty)
        'updateTransforms': [
          for (final f in serverTimeFields) {'fieldPath': f, 'setToServerValue': 'REQUEST_TIME'},
        ],
      if (mustNotExist) 'currentDocument': {'exists': false},
    };

    final res = await http.post(
      Uri.parse('$_host/v1/$_dbPath:commit'),
      headers: _headers,
      body: jsonEncode({
        'writes': [write],
      }),
    );
    return res.statusCode;
  }

  static Map<String, Object?> _encodeFields(Map<String, Object?> data) =>
      {for (final e in data.entries) e.key: _encode(e.value)};

  static Map<String, Object?> _encode(Object? v) {
    if (v == null) return {'nullValue': null};
    if (v is bool) return {'booleanValue': v};
    if (v is int) return {'integerValue': '$v'};
    if (v is double) return {'doubleValue': v};
    if (v is String) return {'stringValue': v};
    if (v is DateTime) return {'timestampValue': v.toUtc().toIso8601String()};
    if (v is List) return {'arrayValue': {'values': v.map(_encode).toList()}};
    if (v is Map) {
      return {'mapValue': {'fields': _encodeFields(Map<String, Object?>.from(v))}};
    }
    throw ArgumentError('Unsupported value type: ${v.runtimeType}');
  }

  /// The emulator accepts unsigned ID tokens, so tests can act as any user.
  static String _unsignedIdToken(String uid) {
    String b64(Map<String, Object?> json) => base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final header = b64({'alg': 'none', 'typ': 'JWT'});
    final payload = b64({
      'iss': 'https://securetoken.google.com/$projectId',
      'aud': projectId,
      'iat': now,
      'exp': now + 3600,
      'auth_time': now,
      'sub': uid,
      'user_id': uid,
      'email': '$uid@example.test',
      'email_verified': true,
      'firebase': {'sign_in_provider': 'password', 'identities': <String, Object?>{}},
    });
    return '$header.$payload.';
  }
}

/// Put this as a field value to have the emulator fill in the server time
/// (what `FieldValue.serverTimestamp()` does in the app).
class ServerTime {
  const ServerTime();
}

const serverTime = ServerTime();
