import 'package:altme/oidc4vc/helper_function/select_request_object_verification_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('selectRequestObjectVerificationIdentity', () {
    const scid = 'QmZ9BT7AsWf62ubssns11KfiuauuoVk2v3zL8HYbGSFVTU';
    const domain = 'unfold-verifier.77.42.86.24.sslip.io';
    const did = 'did:webvh:$scid:$domain';
    const prefixedDid = 'decentralized_identifier:$did';

    test('selects DID verification for a Draft 20 prefixed DID', () {
      final identity = selectRequestObjectVerificationIdentity(
        clientId: prefixedDid,
        clientIdScheme: null,
        draft22AndAbove: false,
      );

      expect(identity?.clientIdScheme, 'did');
      expect(identity?.clientId, did);
    });

    test('keeps prefixed DID verification for Draft 22 and above', () {
      final identity = selectRequestObjectVerificationIdentity(
        clientId: prefixedDid,
        clientIdScheme: null,
        draft22AndAbove: true,
      );

      expect(identity?.clientIdScheme, 'did');
      expect(identity?.clientId, did);
    });

    test('preserves an explicit client ID scheme', () {
      final identity = selectRequestObjectVerificationIdentity(
        clientId: 'verifier.example',
        clientIdScheme: 'x509_san_dns',
        draft22AndAbove: false,
      );

      expect(identity?.clientIdScheme, 'x509_san_dns');
      expect(identity?.clientId, 'verifier.example');
    });

    test('preserves Draft 22 embedded scheme selection', () {
      final identity = selectRequestObjectVerificationIdentity(
        clientId: 'x509_san_dns:verifier.example',
        clientIdScheme: null,
        draft22AndAbove: true,
      );

      expect(identity?.clientIdScheme, 'x509_san_dns');
      expect(identity?.clientId, 'verifier.example');
    });

    test('does not broaden Draft 20 unprefixed or unsupported identities', () {
      for (final clientId in <String>[
        'verifier.example',
        'unsupported:verifier.example',
      ]) {
        final identity = selectRequestObjectVerificationIdentity(
          clientId: clientId,
          clientIdScheme: null,
          draft22AndAbove: false,
        );

        expect(identity?.clientIdScheme, isNull);
        expect(identity?.clientId, clientId);
      }
    });

    test('preserves explicit redirect and attestation paths', () {
      for (final scheme in <String>['redirect_uri', 'verifier_attestation']) {
        final identity = selectRequestObjectVerificationIdentity(
          clientId: 'verifier.example',
          clientIdScheme: scheme,
          draft22AndAbove: false,
        );

        expect(identity?.clientIdScheme, scheme);
        expect(identity?.clientId, 'verifier.example');
      }
    });

    test('rejects malformed or ambiguous DID prefixes', () {
      for (final clientId in <String>[
        'decentralized_identifier:',
        'decentralized_identifier:not-a-did',
        'decentralized_identifier:did:',
        'decentralized_identifier:did:webvh:',
        'decentralized_identifier:did:webvh:bad value',
        'decentralized_identifier:$prefixedDid',
      ]) {
        expect(
          selectRequestObjectVerificationIdentity(
            clientId: clientId,
            clientIdScheme: null,
            draft22AndAbove: false,
          ),
          isNull,
          reason: clientId,
        );
      }
    });

    test('rejects missing and empty client IDs', () {
      for (final clientId in <Object?>[null, '', 42]) {
        expect(
          selectRequestObjectVerificationIdentity(
            clientId: clientId,
            clientIdScheme: null,
            draft22AndAbove: false,
          ),
          isNull,
        );
      }
    });
  });
}
