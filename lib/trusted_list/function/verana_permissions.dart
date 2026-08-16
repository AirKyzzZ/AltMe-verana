import 'package:altme/app/shared/constants/parameters.dart';
import 'package:altme/app/shared/dio_client/dio_client.dart';

// The VPR list endpoints ignore `pagination.*` entirely and default to 64
// records; `response_max_size` is the parameter that actually widens the
// response. Reading the default would make an accredited issuer beyond record
// 64 look unaccredited, so the ceiling is requested explicitly and a full page
// is treated as truncated rather than complete.
const int veranaPermissionResponseMaxSize = 1000;

const Duration _permissionTimeout = Duration(seconds: 10);

enum VeranaPermissionRole { issuer, verifier }

extension VeranaPermissionRoleX on VeranaPermissionRole {
  String get vprType => switch (this) {
    VeranaPermissionRole.issuer => 'ISSUER',
    VeranaPermissionRole.verifier => 'VERIFIER',
  };

  /// `PermissionType` on the chain: ISSUER = 1, VERIFIER = 2.
  int get vprTypeCode => switch (this) {
    VeranaPermissionRole.issuer => 1,
    VeranaPermissionRole.verifier => 2,
  };

  String get label => switch (this) {
    VeranaPermissionRole.issuer => 'issuer',
    VeranaPermissionRole.verifier => 'verifier',
  };
}

const Set<String> _permissionTypes = <String>{
  'ISSUER',
  'VERIFIER',
  'ISSUER_GRANTOR',
  'VERIFIER_GRANTOR',
  'ECOSYSTEM',
  'HOLDER',
};

class VeranaPermission {
  const VeranaPermission({
    required this.id,
    required this.did,
    required this.schemaId,
    required this.type,
    this.effectiveFrom,
    this.effectiveUntil,
    this.revoked,
    this.slashed,
    this.validationState,
  });

  final String id;
  final String did;
  final String schemaId;
  final String type;
  final String? effectiveFrom;
  final String? effectiveUntil;
  final String? revoked;
  final String? slashed;
  final String? validationState;
}

class VeranaAccreditation {
  const VeranaAccreditation({
    required this.role,
    required this.granted,
    this.schemaId,
    this.permissionId,
    this.reason,
  });

  final VeranaPermissionRole role;
  final bool granted;
  final String? schemaId;
  final String? permissionId;
  final String? reason;
}

class VeranaAccreditationCheck {
  const VeranaAccreditationCheck({
    required this.granted,
    required this.reason,
    this.schemaId,
    this.credentialName,
  });

  /// `null` is could-not-determine, not a refusal: an unreachable registry or
  /// an unmatched schema must never render as "not accredited". Only a VPR
  /// answer sets true or false.
  final bool? granted;
  final String reason;
  final String? schemaId;
  final String? credentialName;
}

class VeranaVctSchemaResolution {
  const VeranaVctSchemaResolution({
    this.schemaId,
    this.credentialName,
    this.unreachable = false,
  });

  final String? schemaId;
  final String? credentialName;
  final bool unreachable;
}

String? _asString(dynamic value) =>
    value is String && value.isNotEmpty ? value : null;

VeranaPermission? parseVeranaPermission(dynamic value) {
  if (value is! Map) return null;

  final type = _asString(value['type']);
  final id = _asString(value['id']);
  final schemaId = _asString(value['schema_id']);
  if (type == null || !_permissionTypes.contains(type)) return null;
  if (id == null || schemaId == null) return null;

  return VeranaPermission(
    id: id,
    schemaId: schemaId,
    type: type,
    did: _asString(value['did']) ?? '',
    effectiveFrom: _asString(value['effective_from']),
    effectiveUntil: _asString(value['effective_until']),
    revoked: _asString(value['revoked']),
    slashed: _asString(value['slashed']),
    validationState: _asString(value['vp_state']),
  );
}

bool isVeranaPermissionActive(VeranaPermission permission, {DateTime? at}) {
  if (permission.revoked != null || permission.slashed != null) return false;
  // PENDING is an application under review, not a grant - the live testnet
  // holds such records.
  if (permission.validationState == 'TERMINATED' ||
      permission.validationState == 'PENDING') {
    return false;
  }

  final now = at ?? DateTime.now();
  if (permission.effectiveFrom != null) {
    final from = DateTime.tryParse(permission.effectiveFrom!);
    if (from != null && from.isAfter(now)) return false;
  }
  if (permission.effectiveUntil != null) {
    final until = DateTime.tryParse(permission.effectiveUntil!);
    if (until != null && !until.isAfter(now)) return false;
  }
  return true;
}

VeranaAccreditation findVeranaAccreditation(
  List<VeranaPermission> permissions, {
  required String did,
  required String schemaId,
  required VeranaPermissionRole role,
  DateTime? at,
}) {
  final forRole = permissions
      .where(
        (permission) =>
            permission.did == did &&
            permission.schemaId == schemaId &&
            permission.type == role.vprType,
      )
      .toList();
  VeranaPermission? live;
  for (final permission in forRole) {
    if (isVeranaPermissionActive(permission, at: at)) {
      live = permission;
      break;
    }
  }

  if (live != null) {
    return VeranaAccreditation(
      role: role,
      granted: true,
      schemaId: schemaId,
      permissionId: live.id,
    );
  }

  final reason =
      forRole.any((permission) => permission.validationState == 'PENDING')
      ? 'A ${role.label} permission for this schema is still pending validation'
      : forRole.isNotEmpty
      ? 'A ${role.label} permission exists for this schema but is no longer '
            'in force'
      : 'No ${role.label} permission for this schema';

  return VeranaAccreditation(
    role: role,
    granted: false,
    schemaId: schemaId,
    reason: reason,
  );
}

final RegExp _vprSchemaId = RegExp(r'/cs/v\d+/js/(\d+)\b');

String? veranaSchemaIdFromVct(String? vct) {
  if (vct == null) return null;
  return _vprSchemaId.firstMatch(vct)?.group(1);
}

/// The SD-JWT type metadata names the schema credential
/// (`relatedJsonSchemaCredentialId`), which names the VPR schema in
/// `credentialSubject.jsonSchema.$id` - the schema the issuer actually
/// committed to, rather than a credential title anyone can reuse. The type
/// metadata's `name` is the display name the consent screens render.
Future<VeranaVctSchemaResolution> resolveVeranaVctSchema({
  required String vct,
  required DioClient client,
}) async {
  final direct = veranaSchemaIdFromVct(vct);
  if (direct != null) return VeranaVctSchemaResolution(schemaId: direct);
  if (!vct.startsWith('https://')) return const VeranaVctSchemaResolution();

  try {
    // One deadline over both fetches, so the chain cannot hold the consent
    // screen for twice the timeout.
    return await Future(() async {
      final dynamic typeMetadata = await client.get(vct);
      final credentialName = typeMetadata is Map
          ? _asString(typeMetadata['name'])
          : null;
      final vtjscId = typeMetadata is Map
          ? _asString(typeMetadata['relatedJsonSchemaCredentialId'])
          : null;
      if (vtjscId == null || !vtjscId.startsWith('https://')) {
        return VeranaVctSchemaResolution(credentialName: credentialName);
      }

      final dynamic vtjsc = await client.get(vtjscId);
      final credentialSubject = vtjsc is Map
          ? vtjsc['credentialSubject']
          : null;
      if (credentialSubject is! Map) {
        return VeranaVctSchemaResolution(credentialName: credentialName);
      }
      // Live VTJSCs carry the pointer as `jsonSchema.$ref` (vpr:…/cs/v1/js/N)
      // with a copy in `credentialSubject.id`; `$id` is the published-schema
      // variant. Read all three.
      final jsonSchema = credentialSubject['jsonSchema'];
      final id =
          (jsonSchema is Map
              ? _asString(jsonSchema[r'$id']) ?? _asString(jsonSchema[r'$ref'])
              : null) ??
          _asString(credentialSubject['id']);
      return VeranaVctSchemaResolution(
        schemaId: veranaSchemaIdFromVct(id),
        credentialName: credentialName,
      );
    }).timeout(_permissionTimeout);
  } catch (_) {
    return const VeranaVctSchemaResolution(unreachable: true);
  }
}

/// Asks the registry only for the permissions bound to this DID, role and
/// schema. Enumerating the full list instead means pulling and parsing every
/// permission on the chain on each check, which fails intermittently on device
/// and surfaces to the user as "registry unreachable".
Future<List<VeranaPermission>?> fetchVeranaPermissionsForDid({
  required DioClient client,
  required String did,
  required VeranaPermissionRole role,
  required String schemaId,
}) async {
  try {
    final dynamic body = await client
        .get(
          '${Parameters.veranaVprApiUrl}/verana/perm/v1/find_with_did',
          queryParameters: <String, dynamic>{
            'did': did,
            'type': role.vprTypeCode,
            'schema_id': schemaId,
          },
        )
        .timeout(_permissionTimeout);
    if (body is! Map) return null;
    final rawPermissions = body['permissions'];
    if (rawPermissions is! List) return null;

    return <VeranaPermission>[
      for (final entry in rawPermissions)
        if (parseVeranaPermission(entry) case final permission?) permission,
    ];
  } catch (_) {
    return null;
  }
}

Future<List<VeranaPermission>?> fetchVeranaPermissions({
  required DioClient client,
  int limit = veranaPermissionResponseMaxSize,
}) async {
  try {
    final dynamic body = await client
        .get(
          '${Parameters.veranaVprApiUrl}/verana/perm/v1/list',
          queryParameters: <String, dynamic>{'response_max_size': limit},
        )
        .timeout(_permissionTimeout);
    if (body is! Map) return null;
    final rawPermissions = body['permissions'];
    if (rawPermissions is! List || rawPermissions.length >= limit) return null;

    return <VeranaPermission>[
      for (final entry in rawPermissions)
        if (parseVeranaPermission(entry) case final permission?) permission,
    ];
  } catch (_) {
    return null;
  }
}

Future<VeranaAccreditationCheck> checkVeranaAccreditation({
  required String did,
  required VeranaPermissionRole role,
  required DioClient client,
  String? vct,
  DateTime? at,
}) async {
  const unreachableReason =
      'The Verana registry could not be reached, so this permission could '
      'not be checked';
  const unresolvedReason =
      'This credential type could not be matched to a Verana schema, so the '
      'permission could not be checked';

  var resolution = const VeranaVctSchemaResolution();
  if (vct != null) {
    resolution = await resolveVeranaVctSchema(vct: vct, client: client);
  }
  if (resolution.unreachable) {
    return VeranaAccreditationCheck(
      granted: null,
      reason: unreachableReason,
      credentialName: resolution.credentialName,
    );
  }
  final schemaId = resolution.schemaId;
  if (schemaId == null) {
    return VeranaAccreditationCheck(
      granted: null,
      reason: unresolvedReason,
      credentialName: resolution.credentialName,
    );
  }

  final permissions = await fetchVeranaPermissionsForDid(
    client: client,
    did: did,
    role: role,
    schemaId: schemaId,
  );
  if (permissions == null) {
    return VeranaAccreditationCheck(
      granted: null,
      reason: unreachableReason,
      schemaId: schemaId,
      credentialName: resolution.credentialName,
    );
  }

  final accreditation = findVeranaAccreditation(
    permissions,
    did: did,
    schemaId: schemaId,
    role: role,
    at: at,
  );
  return VeranaAccreditationCheck(
    granted: accreditation.granted,
    reason: accreditation.granted
        ? 'An active ${role.label} permission covers this schema'
        : accreditation.reason ?? 'No ${role.label} permission for this schema',
    schemaId: schemaId,
    credentialName: resolution.credentialName,
  );
}
