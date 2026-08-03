import 'package:altme/app/shared/constants/parameters.dart';
import 'package:altme/app/shared/dio_client/dio_client.dart';
import 'package:altme/oidc4vc/model/verified_request_context.dart';
import 'package:altme/trusted_list/function/check_issuer_is_trusted.dart';
import 'package:altme/trusted_list/model/trusted_entity.dart';
import 'package:altme/trusted_list/model/trusted_list.dart';
import 'package:altme/trusted_list/model/verana_trust.dart';

/// Extracts requested credential types from a cryptographically verified
/// OID4VP request, retaining the entity model's non-empty `vcTypes` invariant.
List<String> getPresentationVcTypesFromVerifiedRequest(
  VerifiedRequestContext verifiedRequest,
) {
  final dcql = verifiedRequest.payload['dcql_query'];
  if (dcql is Map && dcql['credentials'] is List) {
    final vcts = <String>[];
    for (final credential in dcql['credentials'] as List) {
      final meta = credential is Map ? credential['meta'] : null;
      final vctValues = meta is Map ? meta['vct_values'] : null;
      if (vctValues is List) {
        vcts.addAll(vctValues.map((dynamic e) => e.toString()));
      }
    }
    if (vcts.isNotEmpty) return vcts;
  }
  final pd = verifiedRequest.payload['presentation_definition'];
  if (pd is Map && pd['input_descriptors'] is List) {
    final vcts = <String>[];
    for (final descriptor in pd['input_descriptors'] as List) {
      final constraints = descriptor is Map ? descriptor['constraints'] : null;
      final fields = constraints is Map ? constraints['fields'] : null;
      if (fields is List) {
        for (final field in fields) {
          final filter = field is Map ? field['filter'] : null;
          if (filter is Map && filter['const'] != null) {
            vcts.add(filter['const'].toString());
          }
        }
      }
    }
    if (vcts.isNotEmpty) return vcts;
  }
  return <String>['verana:resolved'];
}

/// Returns an identity only when it originated in a verified request context.
String? getVerifierClientIdFromVerifiedRequest(
  VerifiedRequestContext? verifiedRequest,
) => verifiedRequest?.verifiedClientId;

/// Looks up static verifier trust only for a cryptographically verified
/// request.
TrustedEntity? getStaticVerifierFromVerifiedRequest({
  required TrustedList trustedList,
  required VerifiedRequestContext? verifiedRequest,
}) {
  final clientId = getVerifierClientIdFromVerifiedRequest(verifiedRequest);
  if (clientId == null) return null;
  return getEntityFromTrustedList(
    trustedList,
    clientId,
    TrustedEntityType.verifier,
  );
}

/// The first concrete requested credential type, for the Q3 accreditation
/// check. `null` when the request names none (never the entity model's
/// `verana:resolved` sentinel).
String? getPresentationVctForAccreditation(
  VerifiedRequestContext verifiedRequest,
) {
  for (final vct in getPresentationVcTypesFromVerifiedRequest(
    verifiedRequest,
  )) {
    if (vct != 'verana:resolved') return vct;
  }
  return null;
}

/// Resolves the consent-time trust context with `detail=full`, so the card
/// can render the ECS credentials for any verdict.
Future<VeranaConsentTrust> getVeranaConsentTrust({
  required String did,
  required DioClient client,
}) async {
  if (!did.startsWith('did:')) return VeranaConsentTrust(did: did);
  try {
    final dynamic response = await client
        .get(
          '${Parameters.veranaResolverUrl}/v1/trust/resolve',
          queryParameters: <String, dynamic>{'did': did, 'detail': 'full'},
        )
        .timeout(const Duration(seconds: 10));
    return VeranaConsentTrust(
      did: did,
      details: parseVeranaTrustDetails(response, did),
    );
  } catch (_) {
    return VeranaConsentTrust(did: did);
  }
}

/// Returns a synthesised [TrustedEntity] only when Verana reports the DID as
/// `TRUSTED` (fail-closed: never surface trust we could not positively
/// resolve).
VeranaTrustedEntity? veranaEntityFromConsent({
  required VeranaConsentTrust consent,
  required VerifiedRequestContext verifiedRequest,
  required TrustedEntityType type,
}) {
  final details = consent.details;
  if (details == null || details.trustStatus != VeranaTrustStatus.trusted) {
    return null;
  }
  return VeranaTrustedEntity(
    id: consent.did,
    type: type,
    vcTypes: getPresentationVcTypesFromVerifiedRequest(verifiedRequest),
    resolution: details,
  );
}

/// Resolves a DID's trust status against the Verana trust registry.
///
/// Returns a synthesised [TrustedEntity] only when Verana reports the DID as
/// `TRUSTED`. Returns `null` for a non-DID id, a non-TRUSTED status, or any
/// error (fail-closed: never surface trust we could not positively resolve).
Future<TrustedEntity?> getEntityFromVerana({
  required VerifiedRequestContext? verifiedRequest,
  required TrustedEntityType type,
  required DioClient client,
}) async {
  if (verifiedRequest == null) return null;
  final entityId = verifiedRequest.verifierDid;
  if (entityId == null || !entityId.startsWith('did:')) return null;
  final consent = await getVeranaConsentTrust(did: entityId, client: client);
  return veranaEntityFromConsent(
    consent: consent,
    verifiedRequest: verifiedRequest,
    type: type,
  );
}

Future<VeranaTrustDetails?> getVeranaTrustDetails({
  required String did,
  required DioClient client,
}) async {
  if (!did.startsWith('did:')) return null;
  try {
    final dynamic response = await client
        .get(
          '${Parameters.veranaResolverUrl}/v1/trust/resolve',
          queryParameters: <String, dynamic>{'did': did, 'detail': 'full'},
        )
        .timeout(const Duration(seconds: 15));
    final details = parseVeranaTrustDetails(response, did);
    if (details == null || details.trustStatus != VeranaTrustStatus.trusted) {
      return null;
    }
    return details;
  } catch (_) {
    return null;
  }
}
