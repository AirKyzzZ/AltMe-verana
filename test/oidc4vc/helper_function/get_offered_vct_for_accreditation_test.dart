import 'package:altme/oidc4vc/helper_function/get_offered_vct_for_accreditation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oidc4vc/oidc4vc.dart';

Oidc4vcParameters parameters({
  Map<String, dynamic> credentialOffer = const <String, dynamic>{},
  dynamic credentialConfigurationsSupported,
}) => Oidc4vcParameters(
  oidc4vciDraftType: OIDC4VCIDraftType.draft13,
  useOAuthAuthorizationServerLink: false,
  initialUri: Uri.parse('openid-credential-offer://?redacted'),
  userPinRequired: false,
  issuerState: null,
  issuer: 'https://issuer.example/oid4vci',
  credentialOffer: credentialOffer,
  issuerOpenIdConfiguration: OpenIdConfiguration(
    requirePushedAuthorizationRequests: false,
    credentialConfigurationsSupported: credentialConfigurationsSupported,
  ),
);

void main() {
  test('maps the first offered configuration id to its vct', () {
    final vct = getOfferedVctForAccreditation(
      parameters(
        credentialOffer: <String, dynamic>{
          'credential_configuration_ids': <String>['unfold-attestation'],
        },
        credentialConfigurationsSupported: <String, dynamic>{
          'unfold-attestation': <String, dynamic>{
            'format': 'dc+sd-jwt',
            'vct': 'https://issuer.example/vct/UnfoldAttestation',
          },
        },
      ),
    );

    expect(vct, 'https://issuer.example/vct/UnfoldAttestation');
  });

  test('skips offered ids the issuer metadata does not describe', () {
    final vct = getOfferedVctForAccreditation(
      parameters(
        credentialOffer: <String, dynamic>{
          'credential_configuration_ids': <String>['unknown', 'known'],
        },
        credentialConfigurationsSupported: <String, dynamic>{
          'known': <String, dynamic>{'vct': 'urn:example:known'},
        },
      ),
    );

    expect(vct, 'urn:example:known');
  });

  test('returns null without offered ids or configurations', () {
    expect(getOfferedVctForAccreditation(parameters()), isNull);
    expect(
      getOfferedVctForAccreditation(
        parameters(
          credentialOffer: <String, dynamic>{
            'credential_configuration_ids': <String>['unfold-attestation'],
          },
        ),
      ),
      isNull,
    );
  });
}
