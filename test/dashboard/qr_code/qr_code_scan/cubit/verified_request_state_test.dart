import 'dart:convert';

import 'package:altme/dashboard/qr_code/qr_code_scan/cubit/qr_code_scan_cubit.dart';
import 'package:altme/oidc4vc/model/verified_request_context.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oidc4vc/oidc4vc.dart';

void main() {
  final payload = base64Url
      .encode(
        utf8.encode(
          jsonEncode(<String, dynamic>{
            'client_id': 'did:webvh:verifier',
            'response_type': 'vp_token',
          }),
        ),
      )
      .replaceAll('=', '');
  final verifiedRequest = VerifiedRequestContext.fromVerification(
    verification: VerificationType.verified,
    encodedRequest: 'header.$payload.signature',
  )!;
  final requestUri = Uri.parse(
    'openid-vc://authorize?request_uri=https%3A%2F%2Fverifier.example%2Frequest&'
    'response_type=vp_token',
  );

  test('verified accept host state ignores a changed request URI '
      'after verification', () {
    final accepted = QRCodeScanState(
      uri: requestUri,
    ).acceptHost(verifiedRequest: verifiedRequest);

    expect(accepted.verifiedRequest, verifiedRequest);
    expect(
      accepted.uri?.queryParameters['request'],
      verifiedRequest.encodedRequest,
    );
    expect(accepted.uri?.queryParameters.containsKey('request_uri'), isFalse);
    expect(accepted.uri?.queryParameters['client_id'], 'did:webvh:verifier');
  });

  test('permissive accept host state has no verified request context', () {
    final accepted = QRCodeScanState(uri: requestUri).acceptHost();

    expect(accepted.verifiedRequest, isNull);
    expect(accepted.uri, requestUri);
  });

  test('a new scan cannot inherit a previous verified request context', () {
    final accepted = QRCodeScanState(
      uri: requestUri,
    ).acceptHost(verifiedRequest: verifiedRequest);

    final nextScan = accepted.copyWith(
      uri: Uri.parse('openid-vc://authorize?response_type=vp_token'),
      clearVerifiedRequest: true,
    );

    expect(nextScan.verifiedRequest, isNull);
  });
}
