import 'dart:convert';

import 'package:altme/oidc4vc/helper_function/request_object_verification_boundary.dart';
import 'package:altme/oidc4vc/helper_function/select_request_object_verification_identity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oidc4vc/oidc4vc.dart';

void main() {
  String encodedRequest(
    Map<String, dynamic> payload, {
    Map<String, dynamic> header = const <String, dynamic>{'alg': 'ES256'},
  }) {
    final encodedHeader = base64Url
        .encode(utf8.encode(jsonEncode(header)))
        .replaceAll('=', '');
    final encodedPayload = base64Url
        .encode(utf8.encode(jsonEncode(payload)))
        .replaceAll('=', '');
    return '$encodedHeader.$encodedPayload.signature';
  }

  group('createVerifiedRequestContextForIdentity', () {
    const did = 'did:webvh:verifier';
    const prefixedDid = 'decentralized_identifier:$did';

    test('creates an exact-byte context for a verified Draft 20 DID', () {
      final identity = selectRequestObjectVerificationIdentity(
        clientId: prefixedDid,
        clientIdScheme: null,
        draft22AndAbove: false,
      );
      final request = encodedRequest(const <String, dynamic>{
        'client_id': prefixedDid,
      });

      final context = createVerifiedRequestContextForIdentity(
        identity: identity,
        verification: VerificationType.verified,
        encodedRequest: request,
      );

      expect(context?.encodedRequest, request);
      expect(context?.verifierDid, did);
    });

    test('rejects failed verification results', () {
      final identity = selectRequestObjectVerificationIdentity(
        clientId: prefixedDid,
        clientIdScheme: null,
        draft22AndAbove: false,
      );
      final request = encodedRequest(const <String, dynamic>{
        'client_id': prefixedDid,
      });

      for (final verification in <VerificationType>[
        VerificationType.notVerified,
        VerificationType.unKnown,
      ]) {
        expect(
          createVerifiedRequestContextForIdentity(
            identity: identity,
            verification: verification,
            encodedRequest: request,
          ),
          isNull,
          reason: verification.name,
        );
      }
    });

    test('rejects bytes that the shared verifier would transform', () {
      final identity = selectRequestObjectVerificationIdentity(
        clientId: prefixedDid,
        clientIdScheme: null,
        draft22AndAbove: false,
      );
      final request = encodedRequest(const <String, dynamic>{
        'client_id': prefixedDid,
      });

      expect(
        createVerifiedRequestContextForIdentity(
          identity: identity,
          verification: VerificationType.verified,
          encodedRequest: '$request~unverified-disclosure',
        ),
        isNull,
      );
    });

    test(
      'rejects bypassed and redirect identities even with a verified value',
      () {
        final bypassedIdentity = selectRequestObjectVerificationIdentity(
          clientId: 'verifier.example',
          clientIdScheme: null,
          draft22AndAbove: false,
        );
        final redirectIdentity = selectRequestObjectVerificationIdentity(
          clientId: 'redirect_uri:https://verifier.example/callback',
          clientIdScheme: null,
          draft22AndAbove: true,
        );

        for (final identity in <RequestObjectVerificationIdentity?>[
          bypassedIdentity,
          redirectIdentity,
        ]) {
          expect(
            createVerifiedRequestContextForIdentity(
              identity: identity,
              verification: VerificationType.verified,
              encodedRequest: encodedRequest(const <String, dynamic>{
                'client_id': 'verifier.example',
              }),
            ),
            isNull,
          );
        }
      },
    );

    test('rejects a self-signed x509 leaf with an appended trusted root', () {
      final identity = selectRequestObjectVerificationIdentity(
        clientId: 'verifier.example',
        clientIdScheme: 'x509_san_dns',
        draft22AndAbove: false,
      );
      final request = encodedRequest(
        const <String, dynamic>{
          'client_id_scheme': 'x509_san_dns',
          'client_id': 'verifier.example',
        },
        header: const <String, dynamic>{
          'alg': 'ES256',
          'x5c': <String>[
            'self-signed-attacker-leaf',
            'appended-configured-root',
          ],
        },
      );

      expect(
        createVerifiedRequestContextForIdentity(
          identity: identity,
          verification: VerificationType.verified,
          encodedRequest: request,
        ),
        isNull,
      );
    });

    test('rejects an unsigned attacker verifier attestation', () {
      final identity = selectRequestObjectVerificationIdentity(
        clientId: 'verifier.example',
        clientIdScheme: 'verifier_attestation',
        draft22AndAbove: false,
      );
      final attackerAttestation = encodedRequest(
        const <String, dynamic>{
          'sub': 'verifier.example',
          'cnf': <String, dynamic>{
            'jwk': <String, dynamic>{'kty': 'EC', 'crv': 'P-256'},
          },
        },
        header: const <String, dynamic>{
          'alg': 'none',
          'typ': 'verifier-attestation+jwt',
        },
      );
      final request = encodedRequest(
        const <String, dynamic>{
          'client_id_scheme': 'verifier_attestation',
          'client_id': 'verifier.example',
        },
        header: <String, dynamic>{'alg': 'ES256', 'jwt': attackerAttestation},
      );

      expect(
        createVerifiedRequestContextForIdentity(
          identity: identity,
          verification: VerificationType.verified,
          encodedRequest: request,
        ),
        isNull,
      );
    });

    test('rejects an ambiguous identity before context creation', () {
      final identity = selectRequestObjectVerificationIdentity(
        clientId: prefixedDid,
        clientIdScheme: 'verifier_attestation',
        draft22AndAbove: false,
      );

      expect(identity, isNull);
      expect(
        createVerifiedRequestContextForIdentity(
          identity: identity,
          verification: VerificationType.verified,
          encodedRequest: encodedRequest(const <String, dynamic>{
            'client_id_scheme': 'verifier_attestation',
            'client_id': prefixedDid,
          }),
        ),
        isNull,
      );
    });
  });
}
