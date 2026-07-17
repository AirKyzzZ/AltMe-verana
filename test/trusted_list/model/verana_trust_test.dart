import 'package:altme/trusted_list/model/verana_trust.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const did = 'did:webvh:example';

  test('parses a valid summary with block and time metadata', () {
    final resolution = parseVeranaTrustResolution(<String, dynamic>{
      'did': did,
      'trustStatus': 'TRUSTED',
      'production': true,
      'evaluatedAt': '2026-07-17T08:00:00Z',
      'evaluatedAtBlock': 4380399,
      'expiresAt': '2026-07-18T08:00:00Z',
    }, did);

    expect(resolution?.trustStatus, VeranaTrustStatus.trusted);
    expect(resolution?.production, isTrue);
    expect(resolution?.evaluatedAtBlock, 4380399);
  });

  test('returns null when the summary DID does not match the request', () {
    expect(
      parseVeranaTrustResolution(<String, dynamic>{
        'did': 'did:webvh:other',
        'trustStatus': 'TRUSTED',
        'production': true,
      }, did),
      isNull,
    );
  });

  test('returns null for an unknown trust status', () {
    expect(
      parseVeranaTrustResolution(<String, dynamic>{
        'did': did,
        'trustStatus': 'PENDING',
        'production': true,
      }, did),
      isNull,
    );
  });

  test('returns null when production is not a boolean', () {
    expect(
      parseVeranaTrustResolution(<String, dynamic>{
        'did': did,
        'trustStatus': 'TRUSTED',
        'production': 'true',
      }, did),
      isNull,
    );
  });
}
