import 'package:altme/oidc4vc/helper_function/credential_endpoint_diagnostic.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('credentialEndpointFailureLog', () {
    test('includes only the status and standardized OAuth error code', () {
      final requestOptions = RequestOptions(
        path: 'https://issuer.example/credential?secret=query-token',
      );
      final exception = DioException(
        type: DioExceptionType.badResponse,
        requestOptions: requestOptions,
        response: Response<dynamic>(
          requestOptions: requestOptions,
          statusCode: 400,
          data: const <String, dynamic>{
            'error': 'invalid_proof',
            'error_description': 'proof contained secret material',
            'access_token': 'secret-access-token',
            'proof': 'secret-proof',
          },
        ),
      );

      final log = credentialEndpointFailureLog(exception);

      expect(log, 'stage=credential_endpoint status=400 error=invalid_proof');
      expect(log, isNot(contains('secret')));
      expect(log, isNot(contains('issuer.example')));
      expect(log, isNot(contains('proof contained')));
    });

    test('redacts a non-standard error value', () {
      final requestOptions = RequestOptions(path: '/credential');
      final exception = DioException(
        type: DioExceptionType.badResponse,
        requestOptions: requestOptions,
        response: Response<dynamic>(
          requestOptions: requestOptions,
          statusCode: 500,
          data: const <String, dynamic>{'error': 'server_error token=secret'},
        ),
      );

      expect(
        credentialEndpointFailureLog(exception),
        'stage=credential_endpoint status=500 error=unavailable',
      );
    });

    test('redacts token-shaped values even when their characters are safe', () {
      for (final attackerValue in <String>[
        'superSecretToken_123',
        'eyJhbGciOiJFUzI1NiJ9.e30.signature',
      ]) {
        final requestOptions = RequestOptions(path: '/credential');
        final exception = DioException(
          type: DioExceptionType.badResponse,
          requestOptions: requestOptions,
          response: Response<dynamic>(
            requestOptions: requestOptions,
            statusCode: 400,
            data: <String, dynamic>{'error': attackerValue},
          ),
        );

        final log = credentialEndpointFailureLog(exception);

        expect(log, 'stage=credential_endpoint status=400 error=unavailable');
        expect(log, isNot(contains(attackerValue)));
      }
    });

    test('allows a known OAuth error identifier', () {
      final requestOptions = RequestOptions(path: '/credential');
      final exception = DioException(
        type: DioExceptionType.badResponse,
        requestOptions: requestOptions,
        response: Response<dynamic>(
          requestOptions: requestOptions,
          statusCode: 500,
          data: const <String, dynamic>{'error': 'server_error'},
        ),
      );

      expect(
        credentialEndpointFailureLog(exception),
        'stage=credential_endpoint status=500 error=server_error',
      );
    });

    test('distinguishes a local failure without rendering the exception', () {
      expect(
        credentialEndpointFailureLog(
          Exception('local failure with secret-proof'),
        ),
        'stage=credential_endpoint status=unavailable error=local_exception',
      );
    });
  });
}
