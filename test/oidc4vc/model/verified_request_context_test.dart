import 'dart:convert';

import 'package:altme/oidc4vc/model/verified_request_context.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oidc4vc/oidc4vc.dart';

void main() {
  String encodedRequest(Map<String, dynamic> payload) {
    final encodedPayload = base64Url
        .encode(utf8.encode(jsonEncode(payload)))
        .replaceAll('=', '');
    return 'header.$encodedPayload.signature';
  }

  group('VerifiedRequestContext', () {
    test('retains verified bytes and normalizes a verifier DID', () {
      final context = VerifiedRequestContext.fromVerification(
        verification: VerificationType.verified,
        encodedRequest: encodedRequest(const <String, dynamic>{
          'client_id': 'decentralized_identifier:did:webvh:verifier',
        }),
      );

      expect(context?.encodedRequest, isNotEmpty);
      expect(
        context?.payload['client_id'],
        'decentralized_identifier:did:webvh:verifier',
      );
      expect(context?.verifiedClientId, 'did:webvh:verifier');
      expect(context?.verifierDid, 'did:webvh:verifier');
    });

    test('does not derive Verana identity from a non-DID explicit scheme', () {
      final context = VerifiedRequestContext.fromVerification(
        verification: VerificationType.verified,
        encodedRequest: encodedRequest(const <String, dynamic>{
          'client_id_scheme': 'verifier_attestation',
          'client_id': 'decentralized_identifier:did:webvh:verifier',
        }),
      );

      expect(
        context?.verifiedClientId,
        'decentralized_identifier:did:webvh:verifier',
      );
      expect(context?.verifierDid, isNull);
    });

    test('does not create a context without cryptographic verification', () {
      for (final verification in <VerificationType>[
        VerificationType.notVerified,
        VerificationType.unKnown,
      ]) {
        final context = VerifiedRequestContext.fromVerification(
          verification: verification,
          encodedRequest: encodedRequest(const <String, dynamic>{
            'client_id': 'did:webvh:trusted-verifier',
          }),
        );

        expect(context, isNull, reason: verification.name);
      }
    });

    test('binds a URI to signed request parameters', () {
      final signedPayload = <String, dynamic>{
        'client_id': 'did:webvh:signed-verifier',
        'redirect_uri': 'https://signed.example/redirect',
        'response_uri': 'https://signed.example/response',
        'nonce': 'signed-nonce',
        'state': 'signed-state',
        'response_type': 'vp_token',
        'response_mode': 'direct_post.jwt',
        'client_id_scheme': 'did',
        'scope': 'openid',
        'claims': <String, dynamic>{'vp_token': <String, dynamic>{}},
        'presentation_definition': <String, dynamic>{'id': 'signed-pd'},
        'dcql_query': <String, dynamic>{'credentials': <dynamic>[]},
        'registration': <String, dynamic>{
          'subject_syntax_types_supported': <String>['did:key'],
        },
        'client_metadata': <String, dynamic>{'vp_formats': <String, dynamic>{}},
        'transaction_data': <String, dynamic>{'type': 'signed-transaction'},
      };
      final signedEncodedRequest = encodedRequest(signedPayload);
      final context = VerifiedRequestContext.fromVerification(
        verification: VerificationType.verified,
        encodedRequest: signedEncodedRequest,
      )!;
      final originalUri = Uri.parse(
        'openid-vc://authorize?client_id=did%3Awebvh%3Aattacker&'
        'redirect_uri=https%3A%2F%2Fattacker.example%2Fredirect&'
        'response_uri=https%3A%2F%2Fattacker.example%2Fresponse&'
        'nonce=attacker-nonce&state=attacker-state&response_type=id_token&'
        'response_mode=direct_post&client_id_scheme=redirect_uri&'
        'scope=offline_access&'
        'claims=attacker-claims&presentation_definition=attacker-pd&'
        'dcql_query=attacker-dcql&'
        'registration=attacker-registration&client_metadata=attacker-metadata&'
        'transaction_data=attacker-transaction&request=attacker-request&'
        'request_uri=https%3A%2F%2Fattacker.example%2Fsecond-request&'
        'ui_locales=en',
      );

      final boundUri = context.bindToUri(originalUri);

      expect(boundUri.queryParameters['request'], signedEncodedRequest);
      expect(boundUri.queryParameters.containsKey('request_uri'), isFalse);
      expect(
        boundUri.queryParameters['client_id'],
        'did:webvh:signed-verifier',
      );
      expect(
        boundUri.queryParameters['redirect_uri'],
        'https://signed.example/redirect',
      );
      expect(
        boundUri.queryParameters['response_uri'],
        'https://signed.example/response',
      );
      expect(boundUri.queryParameters['nonce'], 'signed-nonce');
      expect(boundUri.queryParameters['state'], 'signed-state');
      expect(boundUri.queryParameters['response_type'], 'vp_token');
      expect(boundUri.queryParameters['response_mode'], 'direct_post.jwt');
      expect(boundUri.queryParameters['client_id_scheme'], 'did');
      expect(boundUri.queryParameters['scope'], 'openid');
      expect(
        boundUri.queryParameters['claims'],
        jsonEncode(signedPayload['claims']),
      );
      expect(
        boundUri.queryParameters['presentation_definition'],
        jsonEncode(signedPayload['presentation_definition']),
      );
      expect(
        boundUri.queryParameters['dcql_query'],
        jsonEncode(signedPayload['dcql_query']),
      );
      expect(
        boundUri.queryParameters['registration'],
        jsonEncode(signedPayload['registration']),
      );
      expect(
        boundUri.queryParameters['client_metadata'],
        jsonEncode(signedPayload['client_metadata']),
      );
      expect(
        boundUri.queryParameters['transaction_data'],
        jsonEncode(signedPayload['transaction_data']),
      );
      expect(boundUri.queryParameters['ui_locales'], 'en');
    });
  });
}
