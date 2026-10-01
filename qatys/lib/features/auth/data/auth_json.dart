import '../domain/session.dart';
import '../domain/student.dart';

// TODO(confirm): docs/api.md does not define the login response body.
// Expected: `{ "token": "<jwt>", "student": { "student_id", "email", "full_name" } }`.
Session sessionFromJson(Map<String, Object?> json) {
  final student = json['student'];
  if (student is! Map<String, Object?>) {
    throw const FormatException('Field "student" is not an object');
  }
  return Session(
    token: _field<String>(json, 'token'),
    student: studentFromJson(student),
  );
}

Student studentFromJson(Map<String, Object?> json) => Student(
  id: _field<int>(json, 'student_id'),
  email: _field<String>(json, 'email'),
  fullName: _field<String>(json, 'full_name'),
);

Map<String, Object?> studentToJson(Student student) => {
  'student_id': student.id,
  'email': student.email,
  'full_name': student.fullName,
};

T _field<T>(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is T) return value;
  throw FormatException(
    'Field "$key" expected $T, got ${value.runtimeType}: $value',
  );
}
