import 'package:oidc4vc/oidc4vc.dart';

/// The first offered credential's `vct`, for the Q2 accreditation check.
/// `null` when the offer or the issuer metadata names none.
String? getOfferedVctForAccreditation(Oidc4vcParameters oidc4vcParameters) {
  final dynamic configurations = oidc4vcParameters
      .issuerOpenIdConfiguration
      .credentialConfigurationsSupported;
  if (configurations is! Map) return null;

  final dynamic ids =
      oidc4vcParameters.credentialOffer['credential_configuration_ids'] ??
      oidc4vcParameters.credentialOffer['credentials'];
  if (ids is! List) return null;

  for (final dynamic id in ids) {
    if (id is! String) continue;
    final dynamic configuration = configurations[id];
    if (configuration is Map && configuration['vct'] is String) {
      return configuration['vct'] as String;
    }
  }
  return null;
}
