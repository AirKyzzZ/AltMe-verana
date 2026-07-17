import 'package:altme/trusted_list/model/verana_trust.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const did = 'did:webvh:example';

  Map<String, dynamic> trustedDetailsResponse() => <String, dynamic>{
    'did': did,
    'trustStatus': 'TRUSTED',
    'production': true,
    'credentials': <dynamic>[
      <String, dynamic>{
        'ecsType': 'ECS-SERVICE',
        'result': 'VALID',
        'format': 'vc+sd-jwt',
        'issuedBy': 'did:webvh:issuer',
        'presentedBy': 'did:webvh:example',
        'claims': <String, dynamic>{
          'name': 'Unfold Verifier',
          'privacyPolicy': 'https://example.com/privacy',
        },
      },
      <String, dynamic>{
        'ecsType': 'ECS-ORG',
        'result': 'VALID',
        'claims': <String, dynamic>{'name': 'Unfold', 'countryCode': 'FR'},
      },
    ],
  };

  test('parses a valid summary with block and time metadata', () {
    final resolution = parseVeranaTrustResolution(<String, dynamic>{
      'did': did,
      'trustStatus': 'TRUSTED',
      'production': true,
      'evaluatedAt': '2026-07-17T08:00:00Z',
      'evaluatedAtBlock': 4380399,
      'expiresAt': '2026-07-18T08:00:00Z',
    }, did);

    expect(resolution?.trustStatus, VeranaTrustStatus.trusted);
    expect(resolution?.production, isTrue);
    expect(resolution?.evaluatedAtBlock, 4380399);
  });

  test('returns null when the summary DID does not match the request', () {
    expect(
      parseVeranaTrustResolution(<String, dynamic>{
        'did': 'did:webvh:other',
        'trustStatus': 'TRUSTED',
        'production': true,
      }, did),
      isNull,
    );
  });

  test('returns null for an unknown trust status', () {
    expect(
      parseVeranaTrustResolution(<String, dynamic>{
        'did': did,
        'trustStatus': 'PENDING',
        'production': true,
      }, did),
      isNull,
    );
  });

  test('returns null when production is not a boolean', () {
    expect(
      parseVeranaTrustResolution(<String, dynamic>{
        'did': did,
        'trustStatus': 'TRUSTED',
        'production': 'true',
      }, did),
      isNull,
    );
  });

  test('parses trusted full details and known credential claims', () {
    final details = parseVeranaTrustDetails(trustedDetailsResponse(), did);

    expect(details?.credentials, hasLength(2));
    expect(details?.credentials.first.ecsType, 'ECS-SERVICE');
    expect(details?.credentials.first.isValid, isTrue);
    expect(details?.credentials.first.issuedBy, 'did:webvh:issuer');
    expect(details?.credentials[1].claims['countryCode'], 'FR');
  });

  test(
    'does not treat invalid or indeterminate credentials as valid evidence',
    () {
      final details = parseVeranaTrustDetails(<String, dynamic>{
        'did': did,
        'trustStatus': 'TRUSTED',
        'production': true,
        'credentials': <dynamic>[
          <String, dynamic>{'ecsType': 'ECS-SERVICE', 'result': 'INVALID'},
          <String, dynamic>{'ecsType': 'ECS-ORG'},
          <String, dynamic>{'ecsType': 'ECS-SERVICE', 'result': 'UNKNOWN'},
        ],
      }, did);

      expect(details?.credentials, hasLength(3));
      expect(
        details?.credentials.every((credential) => !credential.isValid),
        isTrue,
      );
    },
  );

  test('rejects full details for a mismatched DID', () {
    expect(
      parseVeranaTrustDetails(<String, dynamic>{
        'did': 'did:webvh:other',
        'trustStatus': 'TRUSTED',
        'production': true,
      }, did),
      isNull,
    );
  });

  test('sanitizes display strings', () {
    expect(veranaDisplayString('  Unfold Verifier  '), 'Unfold Verifier');
    expect(veranaDisplayString('   '), isNull);
    expect(veranaDisplayString(<String, dynamic>{}), isNull);
  });

  test('accepts only HTTP(S) URIs', () {
    expect(veranaHttpUri('https://example.com/privacy')?.scheme, 'https');
    expect(veranaHttpUri('http://example.com/terms')?.scheme, 'http');
    expect(veranaHttpUri('javascript:alert(1)'), isNull);
    expect(veranaHttpUri('not a URL'), isNull);
  });
}
