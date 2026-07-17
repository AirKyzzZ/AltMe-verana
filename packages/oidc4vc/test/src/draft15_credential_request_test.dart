import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:oidc4vc/oidc4vc.dart';

void main() {
  test(
    'draft 15 uses a string credential configuration id when legacy metadata '
    'is also present',
    () async {
      const issuer = 'https://issuer.example/oid4vci/example';
      const credentialConfigurationId = 'unfold-attestation';
      const vct = 'https://issuer.example/vct/unfold-attestation';
      final metadata = OpenIdConfiguration.fromJson(const <String, dynamic>{
        'credential_issuer': issuer,
        'credential_endpoint': '$issuer/credential',
        'nonce_endpoint': '$issuer/nonce',
        'credentials_supported': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': credentialConfigurationId,
            'format': 'vc+sd-jwt',
            'vct': vct,
          },
        ],
        'credential_configurations_supported': <String, dynamic>{
          credentialConfigurationId: <String, dynamic>{
            'format': 'dc+sd-jwt',
            'cryptographic_binding_methods_supported': <String>['jwk'],
            'credential_signing_alg_values_supported': <String>['ES256'],
            'proof_types_supported': <String, dynamic>{
              'jwt': <String, dynamic>{
                'proof_signing_alg_values_supported': <String>['ES256'],
              },
            },
            'vct': vct,
          },
        },
      });
      final oidc4vc = OIDC4VC();

      final credential = await oidc4vc.getCredentialData(
        openIdConfiguration: metadata,
        credential: credentialConfigurationId,
      );

      expect(credential.$1, credentialConfigurationId);
      expect(credential.$2, isNull);
      expect(credential.$3, isNull);
      expect(credential.$4, vct);
      expect(credential.$5, VCFormatType.dcSdJWT.vcValue);

      const did = 'did:jwk:example';
      const kid = '$did#0';
      const privateKey = <String, dynamic>{
        'kty': 'EC',
        'crv': 'P-256',
        'd': 'amrwK13ZiYoJ5g0fc6MvXc86RB9ID8VuK_dMowU68FE',
        'x': 'fJQ2c9P_YDep3jzidwykcSlyoC4omqBvd9RHP1nz0cw',
        'y': 'K7VxrW-S1ONuX5cxrWIltF36ac1K8kj9as_o5cyc2zk',
      };
      final request = await oidc4vc.buildCredentialData(
        oidc4vcParameters: Oidc4vcParameters(
          oidc4vciDraftType: OIDC4VCIDraftType.draft15,
          useOAuthAuthorizationServerLink: false,
          initialUri: Uri(),
          userPinRequired: false,
          issuerState: null,
          issuer: issuer,
          credentialOffer: const <String, dynamic>{
            'credential_configuration_ids': <String>[credentialConfigurationId],
          },
          issuerOpenIdConfiguration: metadata,
        ),
        issuerTokenParameters: IssuerTokenParameters(
          privateKey: privateKey,
          did: did,
          kid: kid,
          issuer: issuer,
          mediaType: MediaType.proofOfOwnership,
          proofHeaderType: ProofHeaderType.kid,
          clientType: ClientType.did,
          clientId: did,
        ),
        credentialType: credential.$1,
        types: credential.$2,
        format: credential.$5,
        cryptoHolderBinding: true,
        clientAuthentication: ClientAuthentication.clientId,
        credentialIdentifier: null,
        nonce: 'redacted-nonce',
        vct: credential.$4,
        credentialDefinition: credential.$3,
        proofType: ProofType.jwt,
        did: did,
        kid: kid,
        privateKey: jsonEncode(privateKey),
        formatsSupported: const <VCFormatType>[VCFormatType.dcSdJWT],
        clientId: null,
      );

      expect(
        request.keys,
        containsAll(<String>['proof', 'credential_configuration_id']),
      );
      expect(request['credential_configuration_id'], credentialConfigurationId);
      expect(request.containsKey('format'), isFalse);
      expect(request.containsKey('vct'), isFalse);

      final proof = request['proof'] as Map<String, dynamic>;
      expect(proof['proof_type'], ProofType.jwt.value);
      final jwt = proof['jwt'] as String;
      final header =
          jsonDecode(
                utf8.decode(
                  base64Url.decode(base64Url.normalize(jwt.split('.').first)),
                ),
              )
              as Map<String, dynamic>;
      expect(header['typ'], MediaType.proofOfOwnership.typ);
      expect(header['alg'], 'ES256');
      expect(header['kid'], kid);
    },
  );

  test('legacy credential map keeps its legacy metadata when both generations '
      'are present', () async {
    final metadata = OpenIdConfiguration.fromJson(const <String, dynamic>{
      'credentials_supported': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'legacy-attestation',
          'format': 'jwt_vc',
          'types': <String>['VerifiableCredential', 'LegacyAttestation'],
        },
      ],
      'credential_configurations_supported': <String, dynamic>{
        'LegacyAttestation': <String, dynamic>{
          'format': 'dc+sd-jwt',
          'vct': 'https://issuer.example/vct/current-attestation',
        },
      },
    });

    final credential = await OIDC4VC().getCredentialData(
      openIdConfiguration: metadata,
      credential: const <String, dynamic>{
        'format': 'jwt_vc',
        'types': <String>['VerifiableCredential', 'LegacyAttestation'],
      },
    );

    expect(credential.$1, 'LegacyAttestation');
    expect(credential.$2, const <String>[
      'VerifiableCredential',
      'LegacyAttestation',
    ]);
    expect(credential.$3, isNull);
    expect(credential.$4, isNull);
    expect(credential.$5, 'jwt_vc');
  });

  test('string configuration id falls back to legacy metadata', () async {
    final metadata = OpenIdConfiguration.fromJson(const <String, dynamic>{
      'credentials_supported': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'legacy-attestation',
          'format': 'vc+sd-jwt',
          'types': <String>['VerifiableCredential', 'LegacyAttestation'],
        },
      ],
      'credential_configurations_supported': <String, dynamic>{
        'modern-attestation': <String, dynamic>{
          'format': 'dc+sd-jwt',
          'vct': 'https://issuer.example/vct/modern-attestation',
        },
      },
    });

    final credential = await OIDC4VC().getCredentialData(
      openIdConfiguration: metadata,
      credential: 'legacy-attestation',
    );

    expect(credential.$1, 'legacy-attestation');
    expect(credential.$2, const <String>[
      'VerifiableCredential',
      'LegacyAttestation',
    ]);
    expect(credential.$3, isNull);
    expect(credential.$4, isNull);
    expect(credential.$5, 'vc+sd-jwt');
  });
}
