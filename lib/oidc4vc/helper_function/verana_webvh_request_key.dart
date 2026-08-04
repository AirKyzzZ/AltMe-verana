import 'package:dio/dio.dart';

/// Resolves the public key a `did:webvh` verifier signed its request
/// object with.
///
/// The OIDC4VC package resolves did:web, did:key and did:jwk, but not
/// did:webvh, so a verifier identifying as
/// `client_id=decentralized_identifier:did:webvh:<scid>:<host>` fails
/// signature verification and the wallet reports "The request is invalid"
/// after the user has already consented.
///
/// A did:webvh names a host, and that host publishes the same verification
/// methods as a did:web alias at `/.well-known/did.json`. The alias document
/// ids carry the did:web prefix while the JWS `kid` carries the did:webvh
/// one, so the match is on the fragment.
///
/// Limitation, deliberately taken: this trusts the document served over TLS
/// by the host the DID names, exactly as did:web does. It does NOT replay
/// the did:webvh log, so the SCID and proof chain are not verified here.
/// Full webvh verification belongs in the OIDC4VC package.
Future<Map<String, dynamic>?> resolveWebvhRequestKey({
  required String did,
  required String? kid,
  Dio? dio,
}) async {
  if (!did.startsWith('did:webvh:')) return null;

  final parts = did.split(':');
  // did:webvh:<scid>:<host>[:<path>...]
  if (parts.length < 4) return null;
  final host = parts[3];
  if (host.isEmpty) return null;
  final path = parts.length > 4 ? '/${parts.sublist(4).join('/')}' : '';

  final client = dio ?? Dio();
  late final Response<dynamic> response;
  try {
    response = await client.get<dynamic>(
      'https://$host$path/.well-known/did.json',
      options: Options(
        responseType: ResponseType.json,
        receiveTimeout: const Duration(seconds: 20),
        sendTimeout: const Duration(seconds: 20),
      ),
    );
  } catch (_) {
    return null;
  }

  final document = response.data;
  if (document is! Map) return null;

  final methods = <Map<String, dynamic>>[];
  const sections = ['verificationMethod', 'assertionMethod', 'authentication'];
  for (final entry in sections) {
    final value = document[entry];
    if (value is List) {
      for (final item in value) {
        if (item is Map) methods.add(Map<String, dynamic>.from(item));
      }
    }
  }
  if (methods.isEmpty) return null;

  final fragment =
      kid != null && kid.contains('#') ? kid.split('#').last : null;

  Map<String, dynamic>? pick(bool Function(Map<String, dynamic>) test) {
    for (final method in methods) {
      if (test(method)) {
        final jwk = method['publicKeyJwk'];
        if (jwk is Map) return Map<String, dynamic>.from(jwk);
      }
    }
    return null;
  }

  if (fragment != null) {
    final matched = pick(
      (method) => method['id'].toString().split('#').last == fragment,
    );
    if (matched != null) return matched;
  }

  // No usable kid: fall back to the only key that can carry a JWK at all.
  return pick((method) => method['publicKeyJwk'] is Map);
}
