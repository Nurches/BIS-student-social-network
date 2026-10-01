class Student {
  const Student({
    required this.id,
    required this.email,
    required this.fullName,
  });

  final int id;

  /// University email only (BR-01).
  final String email;
  final String fullName;
}

final _universityEmail = RegExp(r'^[^@\s]+@kbtu\.kz$', caseSensitive: false);

/// BR-01, mirrors `chk_university_email` in docs/schema.sql. Checked on the
/// client only to give a clear message before any request is sent; the
/// server enforces it again.
bool isUniversityEmail(String email) => _universityEmail.hasMatch(email.trim());
