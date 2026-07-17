# P0 trust hardening report

## Status

Implemented the approved no-dependency safeguard. Trust evidence that the app
cannot currently verify cryptographically now fails closed instead of creating
a positive trust context.

- `x509_san_dns` and `verifier_attestation` request objects are rejected by the
  strict scan path with an explicit cryptographic-verification error.
- Only a successfully verified DID request can create a
  `VerifiedRequestContext` and reach static or Verana positive trust.
- The permissive path retains the existing explicit untrusted consent. Redirect
  requests also remain outside the verified request context.
- Listed issuers are rejected before signed metadata is decoded or used. An
  unsigned unlisted issuer still reaches the prominent warning dialog.

Full X.509, verifier-attestation, and signed-issuer-metadata support remains
unavailable until AltMe has a vetted RFC 5280 validation boundary. This change
does not weaken strict verification or add a dependency.

## Reviewer findings verified at `a57619c`

### X.509 request objects

`checkX509` parses the leaf from the request object's `x5c`, string-parses its
SAN extension, and returns the leaf key. Its chain-verification call is
commented out, and `verifyX509Chain` returns `true` after parsing the supplied
certificates. A self-signed attacker leaf with a matching SAN and an appended
configured root could therefore provide the key used to verify its own request
object.

### Verifier attestation

`checkVerifierAttestation` decodes the embedded attestation JWT, checks `sub`
and the shape of `cnf.jwk`, then returns the unverified JWK. It does not validate
the attestation JWS, trust its issuer, enforce `typ`, or validate time claims.

### Listed issuer signed metadata

`getIssuerOpenIdConfiguration` decodes signed metadata without verifying its
JWS. `isCertificateValid` accepted a literal `x5c` match without proving the
leaf chained to that anchor or signed the JWS. The listed-issuer host flow also
read VCT authorization from unsigned metadata while using decoded signed values
for issuance.

## Implemented safeguard

### Request objects

- `lib/dashboard/qr_code/qr_code_scan/cubit/qr_code_scan_cubit.dart` rejects
  `x509_san_dns` and `verifier_attestation` before either unsafe helper can
  supply a request-verification key.
- `lib/oidc4vc/helper_function/request_object_verification_boundary.dart`
  accepts only DID identities when constructing `VerifiedRequestContext`, so a
  future call-site regression cannot promote either unavailable scheme.
- The shared `checkX509` helper was not globally disabled because other UI code
  uses it outside this request trust boundary.

### Issuer metadata

- `lib/oidc4vc/helper_function/oidc4vci_accept_host.dart` fails closed as soon
  as an issuer matches the trusted list. It no longer decodes signed metadata,
  compares a literal certificate, reads an unsigned VCT for authorization, or
  presents a positive trusted-issuer dialog.
- The unlisted branch is unchanged and retains its explicit warning/demo
  issuance path.

## TDD evidence

The initial focused run failed on all three attacker regressions:

- self-signed X.509 leaf with an appended configured root produced a
  `VerifiedRequestContext`;
- unsigned attacker verifier attestation produced a
  `VerifiedRequestContext`;
- forged listed-issuer metadata replaced endpoints/configuration and reached a
  positive confirmation dialog.

After the safeguard, the same attacker cases fail closed. The compatibility
case proving unsigned unlisted issuers still reach prominent untrusted consent
also remains green.

## Verification

- `dart format --set-exit-if-changed` on the five changed Dart files: clean.
- Focused `flutter analyze` on the five changed Dart files: no issues.
- Focused Flutter suite covering the boundary, issuer host flow, verified
  request state/context, and Verana trust: 36 tests passed.
- `git diff --check`: clean.

## Remaining safe unblock options

To restore positive X.509, verifier-attestation, or listed-issuer signed
metadata trust, use either:

1. a maintained, audited Flutter-compatible dependency that performs full RFC
   5280 path validation against caller-provided DER trust anchors; or
2. a native Android `CertPathValidator(PKIX)` and iOS `SecTrust` boundary with
   explicit anchors and native positive/negative tests.

That implementation must validate the full certificate path, certificate
constraints and validity, exact SAN/subject binding, JOSE algorithm and `typ`,
JWS proof of possession, issuer trust, applicable time claims, and signed
metadata precedence before re-enabling positive trust.
