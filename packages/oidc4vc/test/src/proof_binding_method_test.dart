import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:oidc4vc/oidc4vc.dart';

const _issuer = 'https://issuer.example/oid4vci/example';
const _configurationId = 'demo-credential';
const _vct = 'https://issuer.example/vct/demo-credential';
const _did = 'did:jwk:example';
const _kid = '$_did#0';
const _privateKey = <String, dynamic>{
  'kty': 'EC',
  'crv': 'P-256',
  'd': 'amrwK13ZiYoJ5g0fc6MvXc86RB9ID8VuK_dMowU68FE',
  'x': 'fJQ2c9P_YDep3jzidwykcSlyoC4omqBvd9RHP1nz0cw',
  'y': 'K7VxrW-S1ONuX5cxrWIltF36ac1K8kj9as_o5cyc2zk',
};

OpenIdConfiguration _metadata(List<String>? bindingMethods) {
  return OpenIdConfiguration.fromJson(<String, dynamic>{
    'credential_issuer': _issuer,
    'credential_endpoint': '$_issuer/credential',
    'nonce_endpoint': '$_issuer/nonce',
    'credential_configurations_supported': <String, dynamic>{
      _configurationId: <String, dynamic>{
        'format': 'dc+sd-jwt',
        if (bindingMethods != null)
          'cryptographic_binding_methods_supported': bindingMethods,
        'credential_signing_alg_values_supported': const <String>['ES256'],
        'proof_types_supported': const <String, dynamic>{
          'jwt': <String, dynamic>{
            'proof_signing_alg_values_supported': <String>['ES256'],
          },
        },
        'vct': _vct,
      },
    },
  });
}

Future<Map<String, dynamic>> _proofHeader(
  OpenIdConfiguration metadata,
  ProofHeaderType profileProofHeader,
) async {
  final oidc4vc = OIDC4VC();
  final credential = await oidc4vc.getCredentialData(
    openIdConfiguration: metadata,
    credential: _configurationId,
  );

  final request = await oidc4vc.buildCredentialData(
    oidc4vcParameters: Oidc4vcParameters(
      oidc4vciDraftType: OIDC4VCIDraftType.draft15,
      useOAuthAuthorizationServerLink: false,
      initialUri: Uri(),
      userPinRequired: false,
      issuerState: null,
      issuer: _issuer,
      credentialOffer: const <String, dynamic>{
        'credential_configuration_ids': <String>[_configurationId],
      },
      issuerOpenIdConfiguration: metadata,
    ),
    issuerTokenParameters: IssuerTokenParameters(
      privateKey: _privateKey,
      did: _did,
      kid: _kid,
      issuer: _issuer,
      mediaType: MediaType.proofOfOwnership,
      proofHeaderType: profileProofHeader,
      clientType: ClientType.did,
      clientId: _did,
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
    did: _did,
    kid: _kid,
    privateKey: jsonEncode(_privateKey),
    formatsSupported: const <VCFormatType>[VCFormatType.dcSdJWT],
    clientId: null,
  );

  final proof = request['proof'] as Map<String, dynamic>;
  final jwt = proof['jwt'] as String;
  return jsonDecode(
        utf8.decode(
          base64Url.decode(base64Url.normalize(jwt.split('.').first)),
        ),
      )
      as Map<String, dynamic>;
}

void main() {
  test('a jwk-only issuer gets an embedded jwk proof header even when the '
      'profile asks for kid', () async {
    final header = await _proofHeader(
      _metadata(<String>['jwk']),
      ProofHeaderType.kid,
    );

    expect(header.containsKey('kid'), isFalse);
    expect(header['jwk'], isA<Map<String, dynamic>>());
    expect((header['jwk'] as Map<String, dynamic>)['x'], _privateKey['x']);
    expect((header['jwk'] as Map<String, dynamic>).containsKey('d'), isFalse);
  });

  test('an issuer that also accepts DID binding keeps the profile kid header',
      () async {
    final header = await _proofHeader(
      _metadata(<String>['DID', 'jwk']),
      ProofHeaderType.kid,
    );

    expect(header['kid'], _kid);
    expect(header.containsKey('jwk'), isFalse);
  });

  test('an issuer advertising only DID binding keeps the profile kid header',
      () async {
    final header = await _proofHeader(
      _metadata(<String>['did:key']),
      ProofHeaderType.kid,
    );

    expect(header['kid'], _kid);
    expect(header.containsKey('jwk'), isFalse);
  });

  test('an issuer that advertises no binding method keeps the profile setting',
      () async {
    final header = await _proofHeader(_metadata(null), ProofHeaderType.kid);

    expect(header['kid'], _kid);
    expect(header.containsKey('jwk'), isFalse);
  });

  test('a profile asking for jwk is never downgraded to kid', () async {
    final header = await _proofHeader(
      _metadata(<String>['DID']),
      ProofHeaderType.jwk,
    );

    expect(header.containsKey('kid'), isFalse);
    expect(header['jwk'], isA<Map<String, dynamic>>());
  });
}
