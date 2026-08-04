import 'package:oidc4vc/oidc4vc.dart';

/// Picks the proof-of-possession header the issuer can actually verify.
///
/// An issuer that advertises `jwk` binding and no DID method has no reason to
/// own a DID resolver, so a `kid` holding a DID makes it fail the proof it
/// asked for. The profile setting still wins whenever the metadata leaves any
/// room for it.
ProofHeaderType resolveProofHeaderType({
  required ProofHeaderType profileProofHeaderType,
  required OpenIdConfiguration openIdConfiguration,
  required String credentialType,
}) {
  if (profileProofHeaderType == ProofHeaderType.jwk) {
    return ProofHeaderType.jwk;
  }

  final configurations = openIdConfiguration.credentialConfigurationsSupported;
  if (configurations is! Map<String, dynamic>) return profileProofHeaderType;

  final configuration = configurations[credentialType];
  if (configuration is! Map<String, dynamic>) return profileProofHeaderType;

  final bindingMethods =
      configuration['cryptographic_binding_methods_supported'];
  if (bindingMethods is! List || bindingMethods.isEmpty) {
    return profileProofHeaderType;
  }

  final methods = bindingMethods
      .map((dynamic method) => method.toString().toLowerCase())
      .toList();

  final acceptsDid = methods.any(
    (String method) => method == 'did' || method.startsWith('did:'),
  );
  if (acceptsDid) return profileProofHeaderType;

  return methods.contains('jwk') ? ProofHeaderType.jwk : profileProofHeaderType;
}
