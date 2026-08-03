import 'package:altme/trusted_list/model/verana_trust.dart';

class VeranaEcsAsset {
  const VeranaEcsAsset({required this.uri, this.digest});

  final String uri;
  final String? digest;
}

class VeranaEcsService {
  const VeranaEcsService({
    required this.descriptionFormat,
    this.id,
    this.name,
    this.type,
    this.description,
    this.logo,
    this.minimumAgeRequired,
    this.terms,
    this.privacy,
  });

  final String? id;
  final String? name;
  final String? type;
  final String? description;
  final String descriptionFormat;
  final VeranaEcsAsset? logo;
  final int? minimumAgeRequired;
  final VeranaEcsAsset? terms;
  final VeranaEcsAsset? privacy;
}

class VeranaEcsOrganization {
  const VeranaEcsOrganization({
    this.id,
    this.name,
    this.logo,
    this.registryId,
    this.address,
    this.countryCode,
    this.registryUri,
    this.legalJurisdiction,
    this.organizationKind,
    this.lei,
  });

  final String? id;
  final String? name;
  final VeranaEcsAsset? logo;
  final String? registryId;
  final String? address;
  final String? countryCode;
  final String? registryUri;
  final String? legalJurisdiction;
  final String? organizationKind;
  final String? lei;
}

class VeranaStrippedText {
  const VeranaStrippedText({required this.text, required this.removed});

  final String text;
  final int removed;
}

String? _str(Map<String, dynamic>? claims, String key) {
  final value = claims?[key];
  return value is String && value.isNotEmpty ? value : null;
}

int? _int(Map<String, dynamic>? claims, String key) {
  final value = claims?[key];
  return value is int ? value : null;
}

// The published schemas are v4 (`<thing>Uri` + `<thing>DigestSri`) but the
// deployed testnet services still issue v3 (`<thing>` + `<thing>Hash`, and no
// logo digest at all). Both shapes have to read until every service is
// re-issued.
VeranaEcsAsset? _asset(
  Map<String, dynamic>? claims,
  String v4Uri,
  String v4Digest,
  String v3Uri, [
  String? v3Digest,
]) {
  final uri = _str(claims, v4Uri) ?? _str(claims, v3Uri);
  if (uri == null) return null;
  final digest =
      _str(claims, v4Digest) ??
      (v3Digest != null ? _str(claims, v3Digest) : null);
  return VeranaEcsAsset(uri: uri, digest: digest);
}

bool _isValid(VeranaTrustCredential? credential) =>
    credential?.isValid ?? false;

/// Claims render as facts only from credentials the resolver verified. A
/// revoked or tampered ECS credential still carries claims; they belong in the
/// failure detail, not on the face of the card.
VeranaEcsService? readEcsService(VeranaTrustCredential? credential) {
  if (credential == null || !_isValid(credential)) return null;
  final claims = credential.claims;

  final format = _str(claims, 'descriptionFormat');
  return VeranaEcsService(
    id: _str(claims, 'id'),
    name: _str(claims, 'name'),
    type: _str(claims, 'type'),
    description: _str(claims, 'description'),
    descriptionFormat: format == 'text/markdown'
        ? 'text/markdown'
        : 'text/plain',
    logo: _asset(claims, 'logoUri', 'logoDigestSri', 'logo'),
    minimumAgeRequired: _int(claims, 'minimumAgeRequired'),
    terms: _asset(
      claims,
      'termsAndConditionsUri',
      'termsAndConditionsDigestSri',
      'termsAndConditions',
      'termsAndConditionsHash',
    ),
    privacy: _asset(
      claims,
      'privacyPolicyUri',
      'privacyPolicyDigestSri',
      'privacyPolicy',
      'privacyPolicyHash',
    ),
  );
}

VeranaEcsOrganization? readEcsOrganization(VeranaTrustCredential? credential) {
  if (credential == null || !_isValid(credential)) return null;
  final claims = credential.claims;

  return VeranaEcsOrganization(
    id: _str(claims, 'id'),
    name: _str(claims, 'name'),
    logo: _asset(claims, 'logoUri', 'logoDigestSri', 'logo'),
    registryId: _str(claims, 'registryId'),
    address: _str(claims, 'address'),
    countryCode: _str(claims, 'countryCode')?.toUpperCase(),
    registryUri: _str(claims, 'registryUri'),
    legalJurisdiction: _str(claims, 'legalJurisdiction'),
    organizationKind: _str(claims, 'organizationKind'),
    lei: _str(claims, 'lei'),
  );
}

VeranaTrustCredential? findEcsCredential(
  List<VeranaTrustCredential>? credentials,
  List<String> ecsTypes,
) {
  if (credentials == null) return null;
  for (final credential in credentials) {
    final ecsType = credential.ecsType;
    if (ecsType != null && ecsTypes.contains(ecsType)) return credential;
  }
  return null;
}

VeranaTrustCredential? findServiceCredential(
  List<VeranaTrustCredential>? credentials,
) => findEcsCredential(credentials, const <String>['ECS-SERVICE']);

VeranaTrustCredential? findOrganizationCredential(
  List<VeranaTrustCredential>? credentials,
) => findEcsCredential(credentials, const <String>[
  'ECS-ORG',
  'ECS-ORGANIZATION',
  'ECS-PERSONA',
]);

/// The badge renders only when both mandatory identity credentials verify.
VeranaTrustStatus deriveVerdict(List<VeranaTrustCredential>? credentials) {
  final service = _isValid(findServiceCredential(credentials));
  final organization = _isValid(findOrganizationCredential(credentials));

  if (service && organization) return VeranaTrustStatus.trusted;
  if (service || organization) return VeranaTrustStatus.partial;
  return VeranaTrustStatus.untrusted;
}

/// Wording is fixed by the versioned card at
/// playground/public/trust-card/index.html. Same sentence in every wallet, or
/// the same evaluation reads differently depending on who rendered it.
String describeVerdict(
  VeranaTrustStatus verdict,
  List<VeranaTrustCredential>? credentials,
) {
  if (verdict == VeranaTrustStatus.trusted) {
    return 'Both identity credentials verified against the Verana public '
        'registry';
  }
  if (verdict == VeranaTrustStatus.untrusted) {
    // A service can present structurally valid ECS credentials and still be
    // untrusted, because whoever issued them is not trusted. Saying "neither
    // credential verified" beside two green ticks would be a visible
    // contradiction, so name the reason the resolver actually gave.
    return _isValid(findServiceCredential(credentials)) ||
            _isValid(findOrganizationCredential(credentials))
        ? 'The Verana public registry does not vouch for this service.'
        : 'Neither identity credential verified. This counterparty cannot '
              'present verifiable trust credentials.';
  }
  return _isValid(findServiceCredential(credentials))
      ? 'The service credential verified. Nothing verifies who operates it.'
      : 'The operator credential verified. Nothing verifies the service '
            'itself.';
}

final RegExp _markdownLink = RegExp(r'\[([^\]]*)\]\(([^)]*)\)');
final RegExp _bareUrl = RegExp(r'\bhttps?://\S+', caseSensitive: false);

/// `descriptionFormat` may be `text/markdown` over 4096 characters, rendered
/// on the screen where someone decides whom to trust. A link there is phishing
/// served by the trust component itself, so links are removed and the count is
/// surfaced.
VeranaStrippedText stripLinks(String? description) {
  if (description == null || description.isEmpty) {
    return const VeranaStrippedText(text: '', removed: 0);
  }

  var removed = 0;
  final withoutMarkdown = description.replaceAllMapped(_markdownLink, (match) {
    removed += 1;
    return match.group(1) ?? '';
  });
  final text = withoutMarkdown.replaceAllMapped(_bareUrl, (_) {
    removed += 1;
    return '';
  });

  return VeranaStrippedText(
    text: text.replaceAll(RegExp(r'\s{2,}'), ' ').trim(),
    removed: removed,
  );
}
