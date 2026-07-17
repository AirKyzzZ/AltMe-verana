import 'dart:collection';
import 'dart:convert';

import 'package:jwt_decode/jwt_decode.dart';
import 'package:oidc4vc/oidc4vc.dart';

/// A request object that was cryptographically verified before it entered the
/// wallet flow. This context must never be created from decoded-only data.
class VerifiedRequestContext {
  VerifiedRequestContext._({
    required this.encodedRequest,
    required Map<String, dynamic> payload,
  }) : payload = UnmodifiableMapView(_freezeMap(payload)),
       verifiedClientId = _normalizedClientId(payload['client_id']),
       verifierDid = _verifierDid(payload['client_id']);

  /// Creates a context only for an actual successful cryptographic check.
  static VerifiedRequestContext? fromVerification({
    required VerificationType verification,
    required String encodedRequest,
  }) {
    if (verification != VerificationType.verified) return null;
    final payload = JWTDecode().parseJwt(encodedRequest);
    return VerifiedRequestContext._(
      encodedRequest: encodedRequest,
      payload: payload,
    );
  }

  final String encodedRequest;
  final Map<String, dynamic> payload;
  final String? verifiedClientId;
  final String? verifierDid;

  /// Binds processing to the signed request instead of outer URI parameters.
  Uri bindToUri(Uri uri) {
    final parameters = Map<String, String>.from(uri.queryParameters)
      ..removeWhere(
        (key, _) =>
            _securityParameterNames.contains(key) || payload.containsKey(key),
      );

    for (final entry in payload.entries) {
      if (entry.key == 'request' ||
          entry.key == 'request_uri' ||
          entry.value == null) {
        continue;
      }
      parameters[entry.key] = _queryValue(entry.value);
    }

    parameters['request'] = encodedRequest;
    return uri.replace(queryParameters: parameters);
  }

  static const _securityParameterNames = <String>{
    'request',
    'request_uri',
    'client_id',
    'client_id_scheme',
    'redirect_uri',
    'response_uri',
    'response_type',
    'response_mode',
    'nonce',
    'state',
    'scope',
    'claims',
    'presentation_definition',
    'presentation_definition_uri',
    'dcql_query',
    'registration',
    'client_metadata',
    'client_metadata_uri',
    'transaction_data',
  };

  static String _queryValue(dynamic value) =>
      value is Map || value is List ? jsonEncode(value) : value.toString();

  static Map<String, dynamic> _freezeMap(Map<String, dynamic> input) =>
      <String, dynamic>{
        for (final entry in input.entries) entry.key: _freeze(entry.value),
      };

  static dynamic _freeze(dynamic value) {
    if (value is Map) {
      return UnmodifiableMapView(<String, dynamic>{
        for (final entry in value.entries)
          entry.key.toString(): _freeze(entry.value),
      });
    }
    if (value is List) return List<dynamic>.unmodifiable(value.map(_freeze));
    return value;
  }

  static String? _normalizedClientId(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    const decentralizedIdentifierPrefix = 'decentralized_identifier:';
    if (value.startsWith(decentralizedIdentifierPrefix)) {
      return value.substring(decentralizedIdentifierPrefix.length);
    }
    return value;
  }

  static String? _verifierDid(dynamic value) {
    final clientId = _normalizedClientId(value);
    return clientId?.startsWith('did:') ?? false ? clientId : null;
  }
}
