import 'package:altme/app/shared/dio_client/dio_client.dart';

/// The DID the Verana registry knows a counterparty by.
///
/// A did:webvh agent also publishes a parallel did:web document, and the
/// presentation-exchange rail identifies the verifier by that did:web name.
/// Only the did:webvh form is registered, so the parallel document's
/// `alsoKnownAs` is followed back before anything is asked of the registry.
/// Any other DID, and any failure, is used as given.
Future<String> canonicalVeranaDid({
  required String did,
  required DioClient client,
}) async {
  if (!did.startsWith('did:web:')) return did;

  final url = didWebDocumentUrl(did);
  if (url == null) return did;

  try {
    final dynamic response = await client
        .get(url)
        .timeout(const Duration(seconds: 10));
    if (response is! Map<String, dynamic>) return did;

    final dynamic alsoKnownAs = response['alsoKnownAs'];
    if (alsoKnownAs is! List) return did;

    for (final dynamic entry in alsoKnownAs) {
      if (entry is String && entry.startsWith('did:webvh:')) return entry;
    }
    return did;
  } catch (_) {
    return did;
  }
}

/// `did:web:host:a:b` resolves to `https://host/a/b/did.json`, a host-only
/// identifier to `https://host/.well-known/did.json`.
String? didWebDocumentUrl(String did) {
  if (!did.startsWith('did:web:')) return null;

  final identifier = did.substring('did:web:'.length);
  if (identifier.isEmpty) return null;

  final segments = identifier.split(':').map(Uri.decodeComponent).toList();
  final host = segments.first;
  if (host.isEmpty) return null;

  final path = segments.skip(1).toList();
  return path.isEmpty
      ? 'https://$host/.well-known/did.json'
      : 'https://$host/${path.join('/')}/did.json';
}
