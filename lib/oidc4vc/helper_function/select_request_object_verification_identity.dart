class RequestObjectVerificationIdentity {
  const RequestObjectVerificationIdentity({
    required this.clientId,
    required this.clientIdScheme,
  });

  final String clientId;
  final String? clientIdScheme;
}

const _supportedClientIdSchemes = <String>{
  'did',
  'redirect_uri',
  'verifier_attestation',
  'x509_san_dns',
};

const _supportedEmbeddedClientIdSchemes = <String>{
  'redirect_uri',
  'verifier_attestation',
  'x509_san_dns',
};

const _decentralizedIdentifierPrefix = 'decentralized_identifier:';

RequestObjectVerificationIdentity? selectRequestObjectVerificationIdentity({
  required Object? clientId,
  required Object? clientIdScheme,
  required bool draft22AndAbove,
}) {
  if (clientId is! String || clientId.isEmpty) return null;

  if (clientIdScheme != null) {
    if (clientIdScheme is! String ||
        !_supportedClientIdSchemes.contains(clientIdScheme)) {
      return null;
    }
    if (_hasEmbeddedClientIdScheme(clientId)) return null;
    if (clientIdScheme == 'did') {
      if (!_isValidDid(clientId)) return null;
    } else if (_isValidDid(clientId)) {
      return null;
    }
    return RequestObjectVerificationIdentity(
      clientId: clientId,
      clientIdScheme: clientIdScheme,
    );
  }

  if (clientId.startsWith(_decentralizedIdentifierPrefix)) {
    final did = clientId.substring(_decentralizedIdentifierPrefix.length);
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

  final schemeSeparator = clientId.indexOf(':');
  if (schemeSeparator <= 0 || schemeSeparator == clientId.length - 1) {
    return null;
  }

  final embeddedScheme = clientId.substring(0, schemeSeparator);
  final embeddedClientId = clientId.substring(schemeSeparator + 1);
  if (_supportedEmbeddedClientIdSchemes.contains(embeddedScheme)) {
    return RequestObjectVerificationIdentity(
      clientId: embeddedClientId,
      clientIdScheme: embeddedScheme,
    );
  }

  final parts = clientId.split(':');
  if (parts.length == 3 && _isValidDid(clientId)) {
    return RequestObjectVerificationIdentity(
      clientId: clientId,
      clientIdScheme: null,
    );
  }

  return null;
}

bool _hasEmbeddedClientIdScheme(String clientId) {
  if (clientId.startsWith(_decentralizedIdentifierPrefix)) return true;
  final schemeSeparator = clientId.indexOf(':');
  if (schemeSeparator <= 0) return false;
  return _supportedEmbeddedClientIdSchemes.contains(
    clientId.substring(0, schemeSeparator),
  );
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
