# P0 trust hardening report

## Status

Blocked before implementation by the task's explicit cryptography safety gate.
The current dependencies can verify a JWS after a trusted public key has been
selected, but they cannot safely validate an arbitrary X.509 certificate path
to the configured trust anchors. No production code or tests were changed.

## Reviewer findings verified at `a57619c`

### X.509 request objects

`checkX509` in
`lib/app/shared/helper_functions/helper_functions.dart` parses the leaf from
the request object's `x5c`, string-parses its SAN extension, and returns the
leaf key. The call to `verifyX509Chain` is commented out. The existing
`verifyX509Chain` implementation only parses the supplied certificates and
then returns `true`; its signature checks are also commented out.

Consequently, a self-signed attacker leaf with a matching SAN is accepted even
if the attacker merely appends a configured root certificate to the `x5c`
array. The request-object JWS is then validly verified with the attacker's leaf
key.

### Verifier attestation

`checkVerifierAttestation` calls `JWTDecode.parseJwt` on the JOSE header's
embedded `jwt`, checks only `sub` and the shape of `cnf.jwk`, and returns that
unverified JWK. It does not validate the attestation JWS, establish trust in
its `iss`, enforce `typ`, or validate `exp`, `nbf`, or `iat`. An attacker can
therefore mint an unsigned or attacker-signed attestation containing their own
`cnf.jwk`, then sign the request object with the corresponding private key.

### Listed issuer signed metadata and VCT authorization

`getIssuerOpenIdConfiguration` uses `JWT.decode`, which does not verify the
signed metadata JWS. `isCertificateValid` then succeeds when any literal
`x5c` string appears in `TrustedEntity.rootCertificates`; it neither proves
that the leaf chains to that anchor nor that the JWS was signed by the leaf.

`oidc4vciAcceptHost` correctly creates `issuanceParameters` from the decoded
signed payload, but its allow-list loop reads each `vct` from the original
unsigned `issuerOpenIdConfiguration`. A listed issuer can therefore present an
authorized unsigned VCT while the signed payload replaces the same
configuration with an unauthorized VCT.

## Specification requirements

OpenID4VP 1.0 requires an `x509_san_dns` client identifier to match a
`dNSName` SAN in the leaf, requires the request object to be signed by that
leaf, and requires the wallet to validate the X.509 trust chain. It also
requires the wallet to validate a verifier-attestation JWS and trust its
issuer before using the attested `cnf.jwk`.

OpenID4VCI requires signed issuer metadata to be JWS-protected, its signer to
be trusted before processing, `sub` to match the Credential Issuer identifier,
and signed metadata values to take precedence over unsigned values.

References:

- https://openid.net/specs/openid-4-verifiable-presentations-1_0-final.html#name-defined-client-identifier-p
- https://openid.net/specs/openid-4-verifiable-presentations-1_0-final.html#name-verifier-attestation-jwt
- https://openid.net/specs/openid-4-verifiable-credential-issuance-1_0-final.html#name-signed-metadata
- https://www.rfc-editor.org/rfc/rfc5280.html#section-6

## Exact dependency and platform blocker

- `x509_plus 0.3.3` exposes certificate/extension parsers and public-key
  primitives, but no RFC 5280 path builder or validator. Its public API has no
  chain-verification entry point.
- `jose_plus 0.4.7` can verify the request, attestation, and metadata JWS only
  after the caller supplies a trusted `JsonWebKey`. It does not validate the
  `x5c` path that establishes whether the leaf key is trusted.
- `dart:io SecurityContext` applies configured trust anchors only while a
  `SecureSocket` performs a live TLS handshake. It has no API to validate the
  arbitrary offline `x5c` chain carried by a JOSE header.
- The repository contains no Android `CertPathValidator` or iOS `SecTrust`
  bridge that could perform the platform validation safely.
- Verifier-attestation processing currently receives no trusted attestation
  authority or trust-anchor input. The profile trusted list could be wired to
  the call site, but without a certificate-path validator the attestation
  issuer key still cannot be authenticated safely.

Implementing certificate signature checks, basic constraints, path length,
key usage, extended key usage, critical extensions, validity, name chaining,
anchor selection, and SAN matching directly with ASN.1 and crypto primitives
would be a hand-rolled PKIX validator. That is precisely the unsafe crypto the
task says not to invent.

## Safe unblock options

1. Approve and select a maintained, audited Flutter-compatible dependency that
   performs full RFC 5280 path validation against caller-provided DER trust
   anchors on Android and iOS.
2. Approve a platform boundary: Android `CertificateFactory` plus
   `CertPathValidator(PKIX)` and iOS `SecTrust` with explicit anchors, exposed
   through a narrow MethodChannel and covered by native positive and negative
   tests.

After either option is approved, the Dart layer can safely:

- parse `x5c` strictly and reject malformed, duplicate, or unsupported paths;
- validate the complete path to the exact configured anchor;
- enforce leaf validity, digital-signature usage, CA constraints, and exact
  `dNSName` SAN matching;
- verify request-object, verifier-attestation, and signed-metadata JWS values
  with explicit asymmetric algorithm allow-lists;
- enforce the applicable `typ`, `iss`, `sub`, `exp`, `nbf`, and `iat` claims;
- read offered VCT authorization only from the verified signed metadata
  configuration;
- retain the existing DID/Verana path and unsigned-unlisted warning.

## Required RED fixtures once unblocked

- self-signed leaf with a matching SAN plus an appended configured root;
- valid leaf/intermediate/root chain with request-object proof of possession;
- unsigned and attacker-signed verifier attestations carrying attacker JWKs;
- valid trusted verifier attestation with request-object proof of possession;
- forged signed metadata that reuses a public certificate without its private
  key;
- valid signed metadata chain and JWS;
- signed versus unsigned credential-configuration VCT mismatch, proving only
  the verified signed payload controls authorization.
