class RequestObjectVerificationIdentity {
  const RequestObjectVerificationIdentity({
    required this.clientId,
    required this.clientIdScheme,
  });

  final String clientId;
  final String? clientIdScheme;
}

RequestObjectVerificationIdentity? selectRequestObjectVerificationIdentity({
  required Object? clientId,
  required Object? clientIdScheme,
  required bool draft22AndAbove,
}) {
  if (clientId is! String || clientId.isEmpty) return null;

  if (clientIdScheme != null) {
    if (clientIdScheme is! String || clientIdScheme.isEmpty) return null;
    return RequestObjectVerificationIdentity(
      clientId: clientId,
      clientIdScheme: clientIdScheme,
    );
  }

  const decentralizedIdentifierPrefix = 'decentralized_identifier:';
  if (clientId.startsWith(decentralizedIdentifierPrefix)) {
    final did = clientId.substring(decentralizedIdentifierPrefix.length);
    if (!_isValidDid(did)) return null;
    return RequestObjectVerificationIdentity(
      clientId: did,
      clientIdScheme: 'did',
    );
  }

  if (!draft22AndAbove) {
    return RequestObjectVerificationIdentity(
      clientId: clientId,
      clientIdScheme: null,
    );
  }

  final parts = clientId.split(':');
  if (parts.length == 2 && parts.every((part) => part.isNotEmpty)) {
    return RequestObjectVerificationIdentity(
      clientId: parts[1],
      clientIdScheme: parts[0],
    );
  }

  if (parts.length == 3 && parts.first.startsWith('did')) {
    return RequestObjectVerificationIdentity(
      clientId: clientId,
      clientIdScheme: null,
    );
  }

  return null;
}

bool _isValidDid(String value) {
  if (!value.startsWith('did:') || value.endsWith(':')) return false;

  final methodEnd = value.indexOf(':', 4);
  if (methodEnd <= 4 || methodEnd == value.length - 1) return false;

  final method = value.substring(4, methodEnd);
  if (!RegExp(r'^[a-z0-9]+$').hasMatch(method)) return false;

  final methodSpecificId = value.substring(methodEnd + 1);
  for (var index = 0; index < methodSpecificId.length; index++) {
    final codeUnit = methodSpecificId.codeUnitAt(index);
    if (_isAsciiAlphaNumeric(codeUnit) ||
        codeUnit == 0x2E ||
        codeUnit == 0x2D ||
        codeUnit == 0x5F ||
        codeUnit == 0x3A) {
      continue;
    }
    if (codeUnit == 0x25 &&
        index + 2 < methodSpecificId.length &&
        _isHex(methodSpecificId.codeUnitAt(index + 1)) &&
        _isHex(methodSpecificId.codeUnitAt(index + 2))) {
      index += 2;
      continue;
    }
    return false;
  }
  return true;
}

bool _isAsciiAlphaNumeric(int value) =>
    value >= 0x30 && value <= 0x39 ||
    value >= 0x41 && value <= 0x5A ||
    value >= 0x61 && value <= 0x7A;

bool _isHex(int value) =>
    value >= 0x30 && value <= 0x39 ||
    value >= 0x41 && value <= 0x46 ||
    value >= 0x61 && value <= 0x66;
