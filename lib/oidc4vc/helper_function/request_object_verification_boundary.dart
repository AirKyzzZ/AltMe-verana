import 'package:altme/oidc4vc/helper_function/select_request_object_verification_identity.dart';
import 'package:altme/oidc4vc/model/verified_request_context.dart';
import 'package:oidc4vc/oidc4vc.dart';

const _cryptographicallyVerifiedSchemes = <String>{'did'};

VerifiedRequestContext? createVerifiedRequestContextForIdentity({
  required RequestObjectVerificationIdentity? identity,
  required VerificationType verification,
  required String encodedRequest,
}) {
  if (identity == null ||
      encodedRequest.contains('~') ||
      !_cryptographicallyVerifiedSchemes.contains(identity.clientIdScheme)) {
    return null;
  }
  return VerifiedRequestContext.fromVerification(
    verification: verification,
    encodedRequest: encodedRequest,
  );
}
