import 'dart:convert';

import 'package:altme/app/shared/dio_client/dio_client.dart';
import 'package:altme/oidc4vc/model/verified_request_context.dart';
import 'package:altme/trusted_list/function/check_verana_trust.dart';
import 'package:altme/trusted_list/model/trusted_entity.dart';
import 'package:altme/trusted_list/model/trusted_list.dart';
import 'package:altme/trusted_list/model/verana_trust.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:oidc4vc/oidc4vc.dart';

class MockDioClient extends Mock implements DioClient {}

String _jwt(Map<String, dynamic> payload) {
  final encoded = base64Url
      .encode(utf8.encode(jsonEncode(payload)))
      .replaceAll('=', '');
  return 'e30.$encoded.signature';
}

VerifiedRequestContext _verifiedRequest(Map<String, dynamic> payload) =>
    VerifiedRequestContext.fromVerification(
      verification: VerificationType.verified,
      encodedRequest: _jwt(payload),
    )!;

void main() {
  group('getVerifierClientIdFromVerifiedRequest', () {
    test('uses the identity from a verified request context', () {
      final verifiedRequest = VerifiedRequestContext.fromVerification(
        verification: VerificationType.verified,
        encodedRequest: _jwt(<String, dynamic>{
          'client_id': 'did:webvh:verified',
        }),
      );

      expect(
        getVerifierClientIdFromVerifiedRequest(verifiedRequest),
        'did:webvh:verified',
      );
    });

    test('normalizes a decentralized identifier client id', () {
      final verifiedRequest = VerifiedRequestContext.fromVerification(
        verification: VerificationType.verified,
        encodedRequest: _jwt(<String, dynamic>{
          'client_id': 'decentralized_identifier:did:webvh:verified',
        }),
      );

      expect(
        getVerifierClientIdFromVerifiedRequest(verifiedRequest),
        'did:webvh:verified',
      );
    });

    test('rejects a forged request without verified context', () {
      expect(getVerifierClientIdFromVerifiedRequest(null), isNull);
    });

    test('does not resolve a static trusted verifier without context', () {
      final entity = getStaticVerifierFromVerifiedRequest(
        trustedList: TrustedList(
          ecosystem: 'test',
          lastUpdated: '2026-07-17',
          entities: <TrustedEntity>[
            TrustedEntity(
              id: 'did:webvh:trusted-verifier',
              type: TrustedEntityType.verifier,
              vcTypes: const <String>['urn:example:vc'],
            ),
          ],
        ),
        verifiedRequest: null,
      );

      expect(entity, isNull);
    });
  });

  group('getPresentationVcTypes', () {
    test('extracts DCQL vct values', () {
      expect(
        getPresentationVcTypesFromVerifiedRequest(
          _verifiedRequest(<String, dynamic>{
            'dcql_query': <String, dynamic>{
              'credentials': <Map<String, dynamic>>[
                <String, dynamic>{
                  'meta': <String, dynamic>{
                    'vct_values': <String>[
                      'urn:example:one',
                      'urn:example:two',
                    ],
                  },
                },
              ],
            },
          }),
        ),
        <String>['urn:example:one', 'urn:example:two'],
      );
    });

    test('extracts presentation definition constants', () {
      expect(
        getPresentationVcTypesFromVerifiedRequest(
          _verifiedRequest(<String, dynamic>{
            'presentation_definition': <String, dynamic>{
              'input_descriptors': <Map<String, dynamic>>[
                <String, dynamic>{
                  'constraints': <String, dynamic>{
                    'fields': <Map<String, dynamic>>[
                      <String, dynamic>{
                        'filter': <String, dynamic>{'const': 'urn:example:vc'},
                      },
                    ],
                  },
                },
              ],
            },
          }),
        ),
        <String>['urn:example:vc'],
      );
    });
  });

  group('getEntityFromVerana', () {
    const did = 'did:webvh:example';
    late MockDioClient client;

    setUp(() {
      client = MockDioClient();
    });

    test('returns an entity only for the exact trusted DID', () async {
      when(
        () => client.get(any(), queryParameters: any(named: 'queryParameters')),
      ).thenAnswer(
        (_) async => <String, dynamic>{
          'did': did,
          'trustStatus': 'TRUSTED',
          'production': true,
          'evaluatedAtBlock': 4380399,
        },
      );

      final entity = await getEntityFromVerana(
        verifiedRequest: _verifiedRequest(<String, dynamic>{
          'client_id': did,
          'presentation_definition': <String, dynamic>{},
        }),
        type: TrustedEntityType.verifier,
        client: client,
      );

      expect(entity, isA<VeranaTrustedEntity>());
      final veranaEntity = entity! as VeranaTrustedEntity;
      expect(veranaEntity.resolution.trustStatus, VeranaTrustStatus.trusted);
      expect(veranaEntity.resolution.production, isTrue);
      expect(veranaEntity.resolution.evaluatedAtBlock, 4380399);
    });

    for (final response in <Map<String, dynamic>>[
      <String, dynamic>{
        'did': 'did:webvh:other',
        'trustStatus': 'TRUSTED',
        'production': true,
      },
      <String, dynamic>{
        'did': did,
        'trustStatus': 'PARTIAL',
        'production': true,
      },
    ]) {
      test('fails closed for $response', () async {
        when(
          () =>
              client.get(any(), queryParameters: any(named: 'queryParameters')),
        ).thenAnswer((_) async => response);

        final entity = await getEntityFromVerana(
          verifiedRequest: _verifiedRequest(<String, dynamic>{
            'client_id': did,
          }),
          type: TrustedEntityType.verifier,
          client: client,
        );

        expect(entity, isNull);
      });
    }

    test('keeps trust when the resolver reports production false', () async {
      when(
        () => client.get(any(), queryParameters: any(named: 'queryParameters')),
      ).thenAnswer(
        (_) async => <String, dynamic>{
          'did': did,
          'trustStatus': 'TRUSTED',
          'production': false,
        },
      );

      final entity = await getEntityFromVerana(
        verifiedRequest: _verifiedRequest(<String, dynamic>{'client_id': did}),
        type: TrustedEntityType.verifier,
        client: client,
      );

      expect(entity, isA<VeranaTrustedEntity>());
      expect((entity! as VeranaTrustedEntity).resolution.production, isFalse);
    });

    test('does not call the resolver for a non-DID identifier', () async {
      final entity = await getEntityFromVerana(
        verifiedRequest: _verifiedRequest(<String, dynamic>{
          'client_id': 'https://example.com',
        }),
        type: TrustedEntityType.verifier,
        client: client,
      );

      expect(entity, isNull);
      verifyNever(
        () => client.get(any(), queryParameters: any(named: 'queryParameters')),
      );
    });

    test('does not resolve an attested client ID as a Verana DID', () async {
      final entity = await getEntityFromVerana(
        verifiedRequest: _verifiedRequest(<String, dynamic>{
          'client_id_scheme': 'verifier_attestation',
          'client_id': 'decentralized_identifier:$did',
        }),
        type: TrustedEntityType.verifier,
        client: client,
      );

      expect(entity, isNull);
      verifyNever(
        () => client.get(any(), queryParameters: any(named: 'queryParameters')),
      );
    });

    test('does not call the resolver without verified context', () async {
      final entity = await getEntityFromVerana(
        verifiedRequest: null,
        type: TrustedEntityType.verifier,
        client: client,
      );

      expect(entity, isNull);
      verifyNever(
        () => client.get(any(), queryParameters: any(named: 'queryParameters')),
      );
    });
  });

  group('getVeranaTrustDetails', () {
    const did = 'did:webvh:example';
    late MockDioClient client;

    setUp(() {
      client = MockDioClient();
    });

    test('returns full details only for the exact trusted DID', () async {
      when(
        () => client.get(any(), queryParameters: any(named: 'queryParameters')),
      ).thenAnswer(
        (_) async => <String, dynamic>{
          'did': did,
          'trustStatus': 'TRUSTED',
          'production': true,
          'credentials': <Map<String, dynamic>>[
            <String, dynamic>{
              'ecsType': 'ECS-SERVICE',
              'issuedBy': 'did:webvh:issuer',
              'claims': <String, dynamic>{'name': 'Unfold Verifier'},
            },
            <String, dynamic>{
              'ecsType': 'ECS-ORG',
              'claims': <String, dynamic>{'countryCode': 'FR'},
            },
          ],
        },
      );

      final details = await getVeranaTrustDetails(did: did, client: client);

      expect(details, isA<VeranaTrustDetails>());
      expect(details?.credentials, hasLength(2));
      expect(details?.credentials.first.issuedBy, 'did:webvh:issuer');
      expect(details?.credentials[1].claims['countryCode'], 'FR');
      verify(
        () => client.get(
          any(),
          queryParameters: <String, dynamic>{'did': did, 'detail': 'full'},
        ),
      ).called(1);
    });

    for (final response in <Map<String, dynamic>>[
      <String, dynamic>{
        'did': 'did:webvh:other',
        'trustStatus': 'TRUSTED',
        'production': true,
      },
      <String, dynamic>{
        'did': did,
        'trustStatus': 'PARTIAL',
        'production': true,
      },
    ]) {
      test('fails closed for $response', () async {
        when(
          () =>
              client.get(any(), queryParameters: any(named: 'queryParameters')),
        ).thenAnswer((_) async => response);

        expect(await getVeranaTrustDetails(did: did, client: client), isNull);
      });
    }

    test('keeps details when the resolver reports production false', () async {
      when(
        () => client.get(any(), queryParameters: any(named: 'queryParameters')),
      ).thenAnswer(
        (_) async => <String, dynamic>{
          'did': did,
          'trustStatus': 'TRUSTED',
          'production': false,
        },
      );

      final details = await getVeranaTrustDetails(did: did, client: client);

      expect(details, isA<VeranaTrustDetails>());
      expect(details?.production, isFalse);
    });

    test('does not call the resolver for a non-DID identifier', () async {
      expect(
        await getVeranaTrustDetails(did: 'https://example.com', client: client),
        isNull,
      );
      verifyNever(
        () => client.get(any(), queryParameters: any(named: 'queryParameters')),
      );
    });
  });
}
