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
