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

    test('preserves an explicit DID scheme with an unprefixed DID', () {
      final identity = selectRequestObjectVerificationIdentity(
        clientId: did,
        clientIdScheme: 'did',
        draft22AndAbove: false,
      );

      expect(identity?.clientIdScheme, 'did');
      expect(identity?.clientId, did);
    });

    test('rejects a separate scheme combined with an embedded scheme', () {
      for (final entry in <(String, String)>[
        ('did', prefixedDid),
        ('verifier_attestation', prefixedDid),
        ('x509_san_dns', 'x509_san_dns:verifier.example'),
        ('redirect_uri', 'redirect_uri:https://verifier.example/callback'),
      ]) {
        expect(
          selectRequestObjectVerificationIdentity(
            clientId: entry.$2,
            clientIdScheme: entry.$1,
            draft22AndAbove: false,
          ),
          isNull,
          reason: '${entry.$1} with ${entry.$2}',
        );
      }
    });

    test('rejects a non-DID explicit scheme with a DID client ID', () {
      expect(
        selectRequestObjectVerificationIdentity(
          clientId: did,
          clientIdScheme: 'verifier_attestation',
          draft22AndAbove: false,
        ),
        isNull,
      );
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

    test('splits Draft 22 embedded schemes on the first colon', () {
      for (final entry in <(String, String, String)>[
        (
          'redirect_uri:https://verifier.example/callback',
          'redirect_uri',
          'https://verifier.example/callback',
        ),
        (
          'verifier_attestation:urn:example:verifier',
          'verifier_attestation',
          'urn:example:verifier',
        ),
      ]) {
        final identity = selectRequestObjectVerificationIdentity(
          clientId: entry.$1,
          clientIdScheme: null,
          draft22AndAbove: true,
        );

        expect(identity?.clientIdScheme, entry.$2, reason: entry.$1);
        expect(identity?.clientId, entry.$3, reason: entry.$1);
      }
    });

    test('rejects unsupported or empty Draft 22 embedded schemes', () {
      for (final clientId in <String>[
        'unsupported:verifier.example',
        'didnot:method:value',
        'x509_san_uri:https://verifier.example',
        'redirect_uri:',
      ]) {
        expect(
          selectRequestObjectVerificationIdentity(
            clientId: clientId,
            clientIdScheme: null,
            draft22AndAbove: true,
          ),
          isNull,
          reason: clientId,
        );
      }
    });

    test('rejects unsupported or empty explicit schemes', () {
      for (final scheme in <String>['', 'unsupported']) {
        expect(
          selectRequestObjectVerificationIdentity(
            clientId: 'verifier.example',
            clientIdScheme: scheme,
            draft22AndAbove: false,
          ),
          isNull,
          reason: scheme,
        );
      }
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
