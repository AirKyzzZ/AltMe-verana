import 'package:altme/app/app.dart';
import 'package:altme/oidc4vc/helper_function/verify_encoded_data.dart';
import 'package:jwt_decode/jwt_decode.dart';
import 'package:oidc4vc/oidc4vc.dart';

const String _wellKnownSuffix = '/.well-known/openid-credential-issuer';
const String _metadataJwtTyp = 'openidvci-issuer-metadata+jwt';
const Duration _fetchTimeout = Duration(seconds: 10);

typedef VeranaJwsVerification =
    Future<bool> Function({
      required String jws,
      required String did,
      required String kid,
    });

class VeranaSignedIssuer {
  const VeranaSignedIssuer({required this.did, required this.didUrl});

  /// The bare DID that signed the issuer metadata.
  final String did;

  /// The DID URL (with fragment) of the signing key.
  final String didUrl;
}

Future<bool> _verifyWithDidDocument({
  required String jws,
  required String did,
  required String kid,
}) async {
  final verification = await verifyEncodedData(
    issuer: did,
    jwtDecode: JWTDecode(),
    jwt: jws,
    useOAuthAuthorizationServerLink: false,
  );
  return verification == VerificationType.verified;
}

/// The wallet's OID4VCI client only reads the plain JSON issuer metadata, so a
/// DID-identified issuer is indistinguishable from an unsigned one and the
/// issuance path can never trust-resolve its counterparty. Fetch the
/// `application/jwt` variant directly and verify it against the key resolved
/// from the DID document before believing the DID claim - `null` on any
/// failure, never an unverified assertion.
Future<VeranaSignedIssuer?> resolveVeranaSignedIssuerMetadata({
  required String credentialIssuer,
  required DioClient client,
  VeranaJwsVerification? verifyJws,
}) async {
  final issuer = credentialIssuer.endsWith('/')
      ? credentialIssuer.substring(0, credentialIssuer.length - 1)
      : credentialIssuer;
  if (!issuer.startsWith('https://') && !issuer.startsWith('http://')) {
    return null;
  }

  try {
    final dynamic response = await client
        .get(
          '$issuer$_wellKnownSuffix',
          headers: const <String, dynamic>{'accept': 'application/jwt'},
        )
        .timeout(_fetchTimeout);
    if (response is! String) return null;

    final jws = response.trim();
    final parts = jws.split('.');
    if (parts.length != 3 || parts.any((part) => part.isEmpty)) return null;

    final jwtDecode = JWTDecode();
    final header = decodeHeader(jwtDecode: jwtDecode, token: jws);
    final kid = header['kid'];
    if (header['typ'] != _metadataJwtTyp ||
        kid is! String ||
        !kid.startsWith('did:')) {
      return null;
    }

    final payload = decodePayload(jwtDecode: jwtDecode, token: jws);
    if (payload['credential_issuer'] != issuer) return null;

    final did = kid.split('#').first;
    final verified = await (verifyJws ?? _verifyWithDidDocument)(
      jws: jws,
      did: did,
      kid: kid,
    );
    if (!verified) return null;

    return VeranaSignedIssuer(did: did, didUrl: kid);
  } catch (_) {
    return null;
  }
}
