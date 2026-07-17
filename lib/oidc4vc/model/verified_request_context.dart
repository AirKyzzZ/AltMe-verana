import 'dart:collection';

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
    required Map<String, dynamic> payload,
  }) {
    if (verification != VerificationType.verified) return null;
    return VerifiedRequestContext._(
      encodedRequest: encodedRequest,
      payload: payload,
    );
  }

  final String encodedRequest;
  final Map<String, dynamic> payload;
  final String? verifiedClientId;
  final String? verifierDid;

  /// Replaces transport-indirected request material with verified bytes.
  Uri bindToUri(Uri uri) {
    final parameters = Map<String, String>.from(uri.queryParameters)
      ..remove('request_uri')
      ..['request'] = encodedRequest;
    return uri.replace(queryParameters: parameters);
  }

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
