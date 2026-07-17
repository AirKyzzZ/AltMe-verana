import 'package:altme/trusted_list/model/trusted_entity.dart';

enum VeranaTrustStatus { trusted, partial, untrusted }

class VeranaTrustResolution {
  const VeranaTrustResolution({
    required this.did,
    required this.trustStatus,
    required this.production,
    this.evaluatedAt,
    this.evaluatedAtBlock,
    this.expiresAt,
  });

  final String did;
  final VeranaTrustStatus trustStatus;
  final bool production;
  final String? evaluatedAt;
  final int? evaluatedAtBlock;
  final String? expiresAt;
}

class VeranaTrustCredential {
  const VeranaTrustCredential({
    required this.claims,
    this.ecsType,
    this.result,
    this.format,
    this.issuedBy,
    this.presentedBy,
  });

  final String? ecsType;
  final String? result;
  final String? format;
  final String? issuedBy;
  final String? presentedBy;
  final Map<String, dynamic> claims;
}

class VeranaTrustDetails extends VeranaTrustResolution {
  const VeranaTrustDetails({
    required super.did,
    required super.trustStatus,
    required super.production,
    required this.credentials,
    super.evaluatedAt,
    super.evaluatedAtBlock,
    super.expiresAt,
  });

  final List<VeranaTrustCredential> credentials;
}

class VeranaTrustedEntity extends TrustedEntity {
  VeranaTrustedEntity({
    required super.id,
    required super.type,
    required super.vcTypes,
    required this.resolution,
  }) : super(
         name: 'Verana Trust Registry',
         description: 'Trust resolved live via the Verana trust registry.',
       );

  final VeranaTrustResolution resolution;
}

VeranaTrustResolution? parseVeranaTrustResolution(
  dynamic value,
  String requestedDid,
) {
  if (value is! Map || value['did'] != requestedDid) return null;

  final trustStatus = switch (value['trustStatus']) {
    'TRUSTED' => VeranaTrustStatus.trusted,
    'PARTIAL' => VeranaTrustStatus.partial,
    'UNTRUSTED' => VeranaTrustStatus.untrusted,
    _ => null,
  };
  final production = value['production'];
  final evaluatedAt = value['evaluatedAt'];
  final evaluatedAtBlock = value['evaluatedAtBlock'];
  final expiresAt = value['expiresAt'];

  if (trustStatus == null ||
      production is! bool ||
      (evaluatedAt != null && evaluatedAt is! String) ||
      (evaluatedAtBlock != null && evaluatedAtBlock is! int) ||
      (expiresAt != null && expiresAt is! String)) {
    return null;
  }

  return VeranaTrustResolution(
    did: requestedDid,
    trustStatus: trustStatus,
    production: production,
    evaluatedAt: evaluatedAt as String?,
    evaluatedAtBlock: evaluatedAtBlock as int?,
    expiresAt: expiresAt as String?,
  );
}

VeranaTrustDetails? parseVeranaTrustDetails(
  dynamic value,
  String requestedDid,
) {
  final resolution = parseVeranaTrustResolution(value, requestedDid);
  if (resolution == null || value is! Map) return null;

  final rawCredentials = value['credentials'];
  final credentials = <VeranaTrustCredential>[];
  if (rawCredentials is List) {
    for (final credential in rawCredentials) {
      if (credential is! Map) continue;
      final rawClaims = credential['claims'];
      final claims = <String, dynamic>{};
      if (rawClaims is Map) {
        for (final MapEntry<dynamic, dynamic> entry in rawClaims.entries) {
          if (entry.key is String) claims[entry.key as String] = entry.value;
        }
      }
      credentials.add(
        VeranaTrustCredential(
          ecsType: _veranaString(credential['ecsType']),
          result: _veranaString(credential['result']),
          format: _veranaString(credential['format']),
          issuedBy: _veranaString(credential['issuedBy']),
          presentedBy: _veranaString(credential['presentedBy']),
          claims: Map<String, dynamic>.unmodifiable(claims),
        ),
      );
    }
  }

  return VeranaTrustDetails(
    did: resolution.did,
    trustStatus: resolution.trustStatus,
    production: resolution.production,
    evaluatedAt: resolution.evaluatedAt,
    evaluatedAtBlock: resolution.evaluatedAtBlock,
    expiresAt: resolution.expiresAt,
    credentials: List<VeranaTrustCredential>.unmodifiable(credentials),
  );
}

String? veranaDisplayString(dynamic value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

Uri? veranaHttpUri(dynamic value) {
  final text = veranaDisplayString(value);
  if (text == null) return null;
  final uri = Uri.tryParse(text);
  if (uri == null || !uri.hasAuthority) return null;
  return uri.scheme == 'https' || uri.scheme == 'http' ? uri : null;
}

String? _veranaString(dynamic value) => value is String ? value : null;
