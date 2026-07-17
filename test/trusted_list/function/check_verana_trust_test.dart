import 'dart:convert';

import 'package:altme/app/shared/dio_client/dio_client.dart';
import 'package:altme/trusted_list/function/check_verana_trust.dart';
import 'package:altme/trusted_list/model/trusted_entity.dart';
import 'package:altme/trusted_list/model/verana_trust.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockDioClient extends Mock implements DioClient {}

String _jwt(Map<String, dynamic> payload) {
  final encoded = base64Url
      .encode(utf8.encode(jsonEncode(payload)))
      .replaceAll('=', '');
  return 'e30.$encoded.signature';
}

void main() {
  group('getVerifierClientId', () {
    test('prefers the identity from the signed request payload', () {
      expect(
        getVerifierClientId(
          authorizationUriClientId: 'did:webvh:outer',
          requestPayload: <String, dynamic>{'client_id': 'did:webvh:signed'},
        ),
        'did:webvh:signed',
      );
    });

    test('normalizes a decentralized identifier client id', () {
      expect(
        getVerifierClientId(
          authorizationUriClientId: 'did:webvh:outer',
          requestPayload: <String, dynamic>{
            'client_id': 'decentralized_identifier:did:webvh:signed',
          },
        ),
        'did:webvh:signed',
      );
    });

    test('rejects an unsigned request instead of using the outer URI', () {
      expect(
        getVerifierClientId(
          authorizationUriClientId: 'did:webvh:outer',
          requestPayload: null,
        ),
        isNull,
      );
    });

    test('rejects a signed request payload without a client id', () {
      expect(
        getVerifierClientId(
          authorizationUriClientId: 'did:webvh:outer',
          requestPayload: <String, dynamic>{},
        ),
        isNull,
      );
    });

    test('rejects an empty signed client id', () {
      expect(
        getVerifierClientId(
          authorizationUriClientId: 'did:webvh:outer',
          requestPayload: <String, dynamic>{'client_id': ''},
        ),
        isNull,
      );
    });
  });

  group('getPresentationVcTypes', () {
    test('extracts DCQL vct values', () {
      final request = _jwt(<String, dynamic>{
        'dcql_query': <String, dynamic>{
          'credentials': <Map<String, dynamic>>[
            <String, dynamic>{
              'meta': <String, dynamic>{
                'vct_values': <String>['urn:example:one', 'urn:example:two'],
              },
            },
          ],
        },
      });

      expect(getPresentationVcTypes(request), <String>[
        'urn:example:one',
        'urn:example:two',
      ]);
    });

    test('extracts presentation definition constants', () {
      final request = _jwt(<String, dynamic>{
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
      });

      expect(getPresentationVcTypes(request), <String>['urn:example:vc']);
    });
  });

  group('getEntityFromVerana', () {
    const did = 'did:webvh:example';
    late MockDioClient client;

    setUp(() {
      client = MockDioClient();
    });

    test(
      'returns an entity only for the exact trusted production DID',
      () async {
        when(
          () =>
              client.get(any(), queryParameters: any(named: 'queryParameters')),
        ).thenAnswer(
          (_) async => <String, dynamic>{
            'did': did,
            'trustStatus': 'TRUSTED',
            'production': true,
            'evaluatedAtBlock': 4380399,
          },
        );

        final entity = await getEntityFromVerana(
          entityId: did,
          type: TrustedEntityType.verifier,
          vcTypes: <String>['urn:example:vc'],
          client: client,
        );

        expect(entity, isA<VeranaTrustedEntity>());
        final veranaEntity = entity! as VeranaTrustedEntity;
        expect(veranaEntity.resolution.trustStatus, VeranaTrustStatus.trusted);
        expect(veranaEntity.resolution.production, isTrue);
        expect(veranaEntity.resolution.evaluatedAtBlock, 4380399);
      },
    );

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
      <String, dynamic>{
        'did': did,
        'trustStatus': 'TRUSTED',
        'production': false,
      },
    ]) {
      test('fails closed for $response', () async {
        when(
          () =>
              client.get(any(), queryParameters: any(named: 'queryParameters')),
        ).thenAnswer((_) async => response);

        final entity = await getEntityFromVerana(
          entityId: did,
          type: TrustedEntityType.verifier,
          vcTypes: <String>['urn:example:vc'],
          client: client,
        );

        expect(entity, isNull);
      });
    }

    test('does not call the resolver for a non-DID identifier', () async {
      final entity = await getEntityFromVerana(
        entityId: 'https://example.com',
        type: TrustedEntityType.verifier,
        vcTypes: <String>['urn:example:vc'],
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

    test(
      'returns full details only for the exact trusted production DID',
      () async {
        when(
          () =>
              client.get(any(), queryParameters: any(named: 'queryParameters')),
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
      },
    );

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
      <String, dynamic>{
        'did': did,
        'trustStatus': 'TRUSTED',
        'production': false,
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
