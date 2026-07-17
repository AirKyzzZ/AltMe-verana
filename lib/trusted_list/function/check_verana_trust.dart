import 'package:altme/app/shared/constants/parameters.dart';
import 'package:altme/app/shared/dio_client/dio_client.dart';
import 'package:altme/trusted_list/model/trusted_entity.dart';
import 'package:altme/trusted_list/model/verana_trust.dart';
import 'package:jwt_decode/jwt_decode.dart';

/// Best-effort extraction of the requested credential type(s) from an OID4VP
/// request (DCQL or presentation_definition), used to populate the synthesised
/// Verana [TrustedEntity]. Falls back to a neutral, non-empty value so the
/// entity model's invariant (issuers/verifiers must carry vcTypes) holds even
/// when the request shape is unexpected.
List<String> getPresentationVcTypes(String encodedRequest) {
  try {
    final payload = JWTDecode().parseJwt(encodedRequest);
    final dcql = payload['dcql_query'];
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
    final pd = payload['presentation_definition'];
    if (pd is Map && pd['input_descriptors'] is List) {
      final vcts = <String>[];
      for (final descriptor in pd['input_descriptors'] as List) {
        final constraints = descriptor is Map
            ? descriptor['constraints']
            : null;
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
  } catch (_) {
    // fall through to the neutral default
  }
  return <String>['verana:resolved'];
}

/// Uses the signed request object's client id when one is available.
///
/// The outer authorization URI is transport metadata and may be attacker
/// controlled. AltMe verifies the request object signature against the client
/// id inside that object, so the trust lookup must use the same identity.
String? getVerifierClientId({
  required String? authorizationUriClientId,
  required Map<String, dynamic>? requestPayload,
}) {
  final signedClientId = requestPayload?['client_id'];
  final clientId = signedClientId is String && signedClientId.isNotEmpty
      ? signedClientId
      : authorizationUriClientId;
  const decentralizedIdentifierPrefix = 'decentralized_identifier:';
  if (clientId?.startsWith(decentralizedIdentifierPrefix) ?? false) {
    return clientId!.substring(decentralizedIdentifierPrefix.length);
  }
  return clientId;
}

/// Resolves a DID's trust status against the Verana trust registry.
///
/// Returns a synthesised [TrustedEntity] only when Verana reports the DID as
/// `TRUSTED`. Returns `null` for a non-DID id, a non-TRUSTED status, or any
/// error (fail-closed: never surface trust we could not positively resolve).
Future<TrustedEntity?> getEntityFromVerana({
  required String? entityId,
  required TrustedEntityType type,
  required List<String> vcTypes,
  required DioClient client,
}) async {
  if (entityId == null || !entityId.startsWith('did:')) return null;
  try {
    final dynamic response = await client
        .get(
          '${Parameters.veranaResolverUrl}/v1/trust/resolve',
          queryParameters: <String, dynamic>{
            'did': entityId,
            'detail': 'summary',
          },
        )
        .timeout(const Duration(seconds: 10));
    final resolution = parseVeranaTrustResolution(response, entityId);
    if (resolution == null ||
        resolution.trustStatus != VeranaTrustStatus.trusted ||
        !resolution.production) {
      return null;
    }
    return VeranaTrustedEntity(
      id: entityId,
      type: type,
      vcTypes: vcTypes,
      resolution: resolution,
    );
  } catch (_) {
    return null;
  }
}
