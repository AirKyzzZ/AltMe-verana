import 'package:altme/oidc4vc/model/verified_request_context.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oidc4vc/oidc4vc.dart';

void main() {
  const encodedRequest = 'header.payload.signature';

  group('VerifiedRequestContext', () {
    test('retains verified bytes and normalizes a verifier DID', () {
      final context = VerifiedRequestContext.fromVerification(
        verification: VerificationType.verified,
        encodedRequest: encodedRequest,
        payload: const <String, dynamic>{
          'client_id': 'decentralized_identifier:did:webvh:verifier',
        },
      );

      expect(context?.encodedRequest, encodedRequest);
      expect(context?.verifiedClientId, 'did:webvh:verifier');
      expect(context?.verifierDid, 'did:webvh:verifier');
    });

    test('does not create a context without cryptographic verification', () {
      final context = VerifiedRequestContext.fromVerification(
        verification: VerificationType.notVerified,
        encodedRequest: encodedRequest,
        payload: const <String, dynamic>{
          'client_id': 'did:webvh:trusted-verifier',
        },
      );

      expect(context, isNull);
    });

    test('binds a URI to verified bytes without mutable request_uri', () {
      final context = VerifiedRequestContext.fromVerification(
        verification: VerificationType.verified,
        encodedRequest: encodedRequest,
        payload: const <String, dynamic>{'client_id': 'did:webvh:verifier'},
      )!;
      final originalUri = Uri.parse(
        'openid-vc://authorize?client_id=did%3Awebvh%3Aouter&'
        'request_uri=https%3A%2F%2Fverifier.example%2Frequest&'
        'response_type=vp_token&state=original-state',
      );

      final boundUri = context.bindToUri(originalUri);

      expect(boundUri.queryParameters['request'], encodedRequest);
      expect(boundUri.queryParameters.containsKey('request_uri'), isFalse);
      expect(boundUri.queryParameters['client_id'], 'did:webvh:outer');
      expect(boundUri.queryParameters['response_type'], 'vp_token');
      expect(boundUri.queryParameters['state'], 'original-state');
    });
  });
}
