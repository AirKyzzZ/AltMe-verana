import 'package:dio/dio.dart';

String credentialEndpointFailureLog(Object error) {
  if (error is! DioException) {
    return 'stage=credential_endpoint '
        'status=unavailable error=local_exception';
  }

  final status = error.response?.statusCode?.toString() ?? 'unavailable';
  final data = error.response?.data;
  final value = data is Map ? data['error'] : null;
  final errorCode = value is String && _isSafeErrorCode(value)
      ? value
      : 'unavailable';

  return 'stage=credential_endpoint status=$status error=$errorCode';
}

bool _isSafeErrorCode(String value) {
  if (value.isEmpty || value.length > 80) return false;

  return value.codeUnits.every(
    (codeUnit) =>
        (codeUnit >= 48 && codeUnit <= 57) ||
        (codeUnit >= 65 && codeUnit <= 90) ||
        (codeUnit >= 97 && codeUnit <= 122) ||
        codeUnit == 45 ||
        codeUnit == 46 ||
        codeUnit == 95 ||
        codeUnit == 126,
  );
}
