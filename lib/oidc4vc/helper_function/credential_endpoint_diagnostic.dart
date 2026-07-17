import 'package:dio/dio.dart';

const _safeErrorCodes = <String>{
  'access_denied',
  'credential_request_denied',
  'insufficient_scope',
  'invalid_client',
  'invalid_credential_request',
  'invalid_dpop_proof',
  'invalid_encryption_parameters',
  'invalid_grant',
  'invalid_nonce',
  'invalid_or_missing_proof',
  'invalid_proof',
  'invalid_request',
  'invalid_scope',
  'invalid_token',
  'invalid_transaction_id',
  'issuance_pending',
  'server_error',
  'temporarily_unavailable',
  'unauthorized_client',
  'unsupported_credential_format',
  'unsupported_credential_type',
  'unsupported_grant_type',
  'use_dpop_nonce',
};

String credentialEndpointFailureLog(Object error) {
  if (error is! DioException) {
    return 'stage=credential_endpoint '
        'status=unavailable error=local_exception';
  }

  final status = error.response?.statusCode?.toString() ?? 'unavailable';
  final data = error.response?.data;
  final value = data is Map ? data['error'] : null;
  final errorCode = value is String && _safeErrorCodes.contains(value)
      ? value
      : 'unavailable';

  return 'stage=credential_endpoint status=$status error=$errorCode';
}
