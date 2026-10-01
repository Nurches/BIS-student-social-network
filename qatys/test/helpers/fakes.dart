import 'dart:convert';

import 'package:qatys/features/auth/data/session_storage.dart';
import 'package:qatys/features/auth/domain/session.dart';
import 'package:qatys/features/auth/domain/student.dart';

class InMemorySessionStorage implements SessionStorage {
  InMemorySessionStorage([this.session]);

  Session? session;
  bool failOnRead = false;

  @override
  Future<Session?> read() async {
    if (failOnRead) throw Exception('keystore is broken');
    return session;
  }

  @override
  Future<void> write(Session session) async => this.session = session;

  @override
  Future<void> clear() async => session = null;
}

String jwtExpiringAt(DateTime expiresAt) {
  String encode(Map<String, Object> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return [
    encode({'alg': 'none'}),
    encode({'sub': '1', 'exp': expiresAt.millisecondsSinceEpoch ~/ 1000}),
    'sig',
  ].join('.');
}

Session sessionExpiringAt(DateTime expiresAt) => Session(
  token: jwtExpiringAt(expiresAt),
  student: const Student(
    id: 1,
    email: 'nurassyl@kbtu.kz',
    fullName: 'Turarbek Nurassyl',
  ),
);
