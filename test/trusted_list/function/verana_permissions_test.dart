import 'package:altme/app/shared/dio_client/dio_client.dart';
import 'package:altme/trusted_list/function/verana_permissions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockDioClient extends Mock implements DioClient {}

const did = 'did:webvh:issuer.example';
const vctUrl = 'https://issuer.example/vct/DemoCredential';
const vtjscUrl = 'https://issuer.example/vtjsc/DemoCredential';

Map<String, dynamic> permission({
  String id = 'perm-1',
  String permissionDid = did,
  String schemaId = '7',
  String type = 'ISSUER',
  String? effectiveFrom,
  String? effectiveUntil,
  String? revoked,
  String? slashed,
  String? vpState,
}) => <String, dynamic>{
  'id': id,
  'did': permissionDid,
  'schema_id': schemaId,
  'type': type,
  if (effectiveFrom != null) 'effective_from': effectiveFrom,
  if (effectiveUntil != null) 'effective_until': effectiveUntil,
  if (revoked != null) 'revoked': revoked,
  if (slashed != null) 'slashed': slashed,
  if (vpState != null) 'vp_state': vpState,
};

void main() {
  late MockDioClient client;

  setUp(() {
    client = MockDioClient();
  });

  void stubRoutes({
    Map<String, dynamic>? typeMetadata,
    Map<String, dynamic>? vtjsc,
    dynamic permissionList,
  }) {
    when(
      () => client.get(any(), queryParameters: any(named: 'queryParameters')),
    ).thenAnswer((invocation) async {
      final uri = invocation.positionalArguments.first as String;
      if (uri == vctUrl) return typeMetadata ?? (throw Exception('no route'));
      if (uri == vtjscUrl) return vtjsc ?? (throw Exception('no route'));
      if (uri.contains('/verana/perm/v1/list')) {
        return permissionList ?? (throw Exception('no route'));
      }
      throw Exception('unexpected uri $uri');
    });
  }

  group('checkVeranaAccreditation', () {
    test(
      'grants an active issuer permission and requests the full VPR page',
      () async {
        stubRoutes(
          permissionList: <String, dynamic>{
            'permissions': <Map<String, dynamic>>[permission()],
          },
        );

        final check = await checkVeranaAccreditation(
          did: did,
          role: VeranaPermissionRole.issuer,
          client: client,
          vct: 'vpr:verana:mainnet/cs/v1/js/7',
        );

        expect(check.granted, isTrue);
        expect(check.schemaId, '7');
        verify(
          () => client.get(
            any(that: contains('/verana/perm/v1/list')),
            queryParameters: <String, dynamic>{'response_max_size': 1000},
          ),
        ).called(1);
      },
    );

    test('refuses definitively when the VPR holds no permission', () async {
      stubRoutes(
        permissionList: <String, dynamic>{
          'permissions': <Map<String, dynamic>>[
            permission(permissionDid: 'did:webvh:someone.else'),
          ],
        },
      );

      final check = await checkVeranaAccreditation(
        did: did,
        role: VeranaPermissionRole.issuer,
        client: client,
        vct: 'vpr:verana:mainnet/cs/v1/js/7',
      );

      expect(check.granted, isFalse);
      expect(check.reason, 'No issuer permission for this schema');
    });

    test('does not read a PENDING application as a grant', () async {
      stubRoutes(
        permissionList: <String, dynamic>{
          'permissions': <Map<String, dynamic>>[permission(vpState: 'PENDING')],
        },
      );

      final check = await checkVeranaAccreditation(
        did: did,
        role: VeranaPermissionRole.issuer,
        client: client,
        vct: 'vpr:verana:mainnet/cs/v1/js/7',
      );

      expect(check.granted, isFalse);
      expect(check.reason, contains('still pending validation'));
    });

    test(
      'does not let an issuer permission satisfy a verifier check',
      () async {
        stubRoutes(
          permissionList: <String, dynamic>{
            'permissions': <Map<String, dynamic>>[permission()],
          },
        );

        final check = await checkVeranaAccreditation(
          did: did,
          role: VeranaPermissionRole.verifier,
          client: client,
          vct: 'vpr:verana:mainnet/cs/v1/js/7',
        );

        expect(check.granted, isFalse);
        expect(check.reason, 'No verifier permission for this schema');
      },
    );

    test(
      'reports could-not-determine for an unmatched credential type',
      () async {
        final check = await checkVeranaAccreditation(
          did: did,
          role: VeranaPermissionRole.issuer,
          client: client,
          vct: 'urn:example:unrelated',
        );

        expect(check.granted, isNull);
        expect(check.reason, contains('could not be matched'));
        verifyNever(
          () =>
              client.get(any(), queryParameters: any(named: 'queryParameters')),
        );
      },
    );

    test(
      'reports could-not-determine when the registry is unreachable',
      () async {
        stubRoutes(permissionList: null);

        final check = await checkVeranaAccreditation(
          did: did,
          role: VeranaPermissionRole.issuer,
          client: client,
          vct: 'vpr:verana:mainnet/cs/v1/js/7',
        );

        expect(check.granted, isNull);
        expect(check.reason, contains('could not be reached'));
      },
    );

    test(
      'resolves the schema through the vct type metadata and the VTJSC',
      () async {
        stubRoutes(
          typeMetadata: <String, dynamic>{
            'name': 'Demo Credential',
            'relatedJsonSchemaCredentialId': vtjscUrl,
          },
          vtjsc: <String, dynamic>{
            'credentialSubject': <String, dynamic>{
              'jsonSchema': <String, dynamic>{
                r'$id': 'https://api.testnet.verana.network/cs/v1/js/12',
              },
            },
          },
          permissionList: <String, dynamic>{
            'permissions': <Map<String, dynamic>>[permission(schemaId: '12')],
          },
        );

        final check = await checkVeranaAccreditation(
          did: did,
          role: VeranaPermissionRole.issuer,
          client: client,
          vct: vctUrl,
        );

        expect(check.granted, isTrue);
        expect(check.schemaId, '12');
        expect(check.credentialName, 'Demo Credential');
      },
    );

    test(r'resolves the schema when the VTJSC carries only $ref, '
        'the live cast shape', () async {
      stubRoutes(
        typeMetadata: <String, dynamic>{
          'name': 'Demo Credential',
          'relatedJsonSchemaCredentialId': vtjscUrl,
        },
        vtjsc: <String, dynamic>{
          'credentialSubject': <String, dynamic>{
            'id': 'vpr:verana:testnet/cs/v1/js/12',
            'jsonSchema': <String, dynamic>{
              r'$ref': 'vpr:verana:testnet/cs/v1/js/12',
            },
          },
        },
        permissionList: <String, dynamic>{
          'permissions': <Map<String, dynamic>>[permission(schemaId: '12')],
        },
      );

      final check = await checkVeranaAccreditation(
        did: did,
        role: VeranaPermissionRole.issuer,
        client: client,
        vct: vctUrl,
      );

      expect(check.granted, isTrue);
      expect(check.schemaId, '12');
    });

    test(
      'treats a full VPR page as truncated, so a grant beyond the cut cannot '
      'read as absent',
      () async {
        stubRoutes(
          permissionList: <String, dynamic>{
            'permissions': List<Map<String, dynamic>>.generate(
              1000,
              (index) => permission(
                id: 'perm-$index',
                permissionDid: 'did:webvh:filler-$index',
              ),
            ),
          },
        );

        final check = await checkVeranaAccreditation(
          did: did,
          role: VeranaPermissionRole.issuer,
          client: client,
          vct: 'vpr:verana:mainnet/cs/v1/js/7',
        );

        expect(check.granted, isNull);
        expect(check.reason, contains('could not be reached'));
      },
    );
  });

  group('isVeranaPermissionActive', () {
    final at = DateTime.utc(2026, 8, 3, 12);

    VeranaPermission parsed(Map<String, dynamic> value) =>
        parseVeranaPermission(value)!;

    test('holds a permission inactive outside its effective window', () {
      expect(
        isVeranaPermissionActive(
          parsed(permission(effectiveFrom: '2026-09-01T00:00:00Z')),
          at: at,
        ),
        isFalse,
      );
      expect(
        isVeranaPermissionActive(
          parsed(permission(effectiveUntil: '2026-08-03T12:00:00Z')),
          at: at,
        ),
        isFalse,
      );
      expect(
        isVeranaPermissionActive(
          parsed(
            permission(
              effectiveFrom: '2026-08-01T00:00:00Z',
              effectiveUntil: '2026-09-01T00:00:00Z',
            ),
          ),
          at: at,
        ),
        isTrue,
      );
    });

    test('revoked, slashed, PENDING and TERMINATED are not grants', () {
      expect(
        isVeranaPermissionActive(
          parsed(permission(revoked: '2026-08-01T00:00:00Z')),
          at: at,
        ),
        isFalse,
      );
      expect(
        isVeranaPermissionActive(
          parsed(permission(slashed: '2026-08-01T00:00:00Z')),
          at: at,
        ),
        isFalse,
      );
      expect(
        isVeranaPermissionActive(
          parsed(permission(vpState: 'PENDING')),
          at: at,
        ),
        isFalse,
      );
      expect(
        isVeranaPermissionActive(
          parsed(permission(vpState: 'TERMINATED')),
          at: at,
        ),
        isFalse,
      );
      expect(
        isVeranaPermissionActive(
          parsed(permission(vpState: 'VALIDATED')),
          at: at,
        ),
        isTrue,
      );
    });
  });

  group('veranaSchemaIdFromVct', () {
    test('extracts the numeric id from a VPR schema pointer', () {
      expect(veranaSchemaIdFromVct('vpr:verana:mainnet/cs/v1/js/7'), '7');
      expect(
        veranaSchemaIdFromVct('https://api.testnet.verana.network/cs/v1/js/12'),
        '12',
      );
      expect(veranaSchemaIdFromVct('urn:example:unrelated'), isNull);
      expect(veranaSchemaIdFromVct(null), isNull);
    });
  });
}
