/// Ghana mobile number validation (024…, 233…, or 9 digits).
bool isValidGhanaPhone(String phone) {
  final d = phone.trim().replaceAll(RegExp(r'\s+'), '');
  return RegExp(r'^0\d{9}$').hasMatch(d) ||
      RegExp(r'^233\d{9}$').hasMatch(d) ||
      RegExp(r'^\d{9}$').hasMatch(d);
}
