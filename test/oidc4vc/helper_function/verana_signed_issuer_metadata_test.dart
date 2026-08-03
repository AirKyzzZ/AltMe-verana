import 'dart:convert';

import 'package:altme/app/shared/dio_client/dio_client.dart';
import 'package:altme/oidc4vc/helper_function/verana_signed_issuer_metadata.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockDioClient extends Mock implements DioClient {}

const credentialIssuer = 'https://issuer.example/oid4vci';
const kid = 'did:webvh:QmT4vPz:issuer.example#openid4vc-development-issuer';

String _segment(Map<String, dynamic> value) =>
    base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');

String jws({
  String typ = 'openidvci-issuer-metadata+jwt',
  String jwsKid = kid,
  String issuer = credentialIssuer,
}) {
  final header = _segment(<String, dynamic>{
    'alg': 'ES256',
    'typ': typ,
    'kid': jwsKid,
  });
  final payload = _segment(<String, dynamic>{'credential_issuer': issuer});
  return '$header.$payload.signature';
}

void main() {
  late MockDioClient client;
  late List<({String jws, String did, String kid})> verifications;
  late bool verdict;

  Future<bool> verifyJws({
    required String jws,
    required String did,
    required String kid,
  }) async {
    verifications.add((jws: jws, did: did, kid: kid));
    return verdict;
  }

  setUp(() {
    client = MockDioClient();
    verifications = [];
    verdict = true;
  });

  void stubResponse(dynamic response) {
    when(
      () => client.get(any(), headers: any(named: 'headers')),
    ).thenAnswer((_) async => response);
  }

  test('resolves the issuer DID from verified DID-signed metadata', () async {
    stubResponse(jws());

    final signedIssuer = await resolveVeranaSignedIssuerMetadata(
      credentialIssuer: credentialIssuer,
      client: client,
      verifyJws: verifyJws,
    );

    expect(signedIssuer, isNotNull);
    expect(signedIssuer!.did, 'did:webvh:QmT4vPz:issuer.example');
    expect(signedIssuer.didUrl, kid);
    expect(verifications, hasLength(1));
    expect(verifications.single.did, 'did:webvh:QmT4vPz:issuer.example');

    final captured = verify(
      () => client.get(captureAny(), headers: captureAny(named: 'headers')),
    ).captured;
    expect(
      captured.first,
      '$credentialIssuer/.well-known/openid-credential-issuer',
    );
    expect((captured[1] as Map<String, dynamic>)['accept'], 'application/jwt');
  });

  test('rejects a plain JSON metadata response', () async {
    stubResponse(<String, dynamic>{'credential_issuer': credentialIssuer});

    expect(
      await resolveVeranaSignedIssuerMetadata(
        credentialIssuer: credentialIssuer,
        client: client,
        verifyJws: verifyJws,
      ),
      isNull,
    );
    expect(verifications, isEmpty);
  });

  test('rejects a JWS without the issuer-metadata typ', () async {
    stubResponse(jws(typ: 'JWT'));

    expect(
      await resolveVeranaSignedIssuerMetadata(
        credentialIssuer: credentialIssuer,
        client: client,
        verifyJws: verifyJws,
      ),
      isNull,
    );
    expect(verifications, isEmpty);
  });

  test('rejects a kid that is not a DID, so x509 cannot claim trust', () async {
    stubResponse(jws(jwsKid: 'x509-cert-key-1'));

    expect(
      await resolveVeranaSignedIssuerMetadata(
        credentialIssuer: credentialIssuer,
        client: client,
        verifyJws: verifyJws,
      ),
      isNull,
    );
    expect(verifications, isEmpty);
  });

  test('rejects metadata bound to a different credential issuer', () async {
    stubResponse(jws(issuer: 'https://rogue.example/oid4vci'));

    expect(
      await resolveVeranaSignedIssuerMetadata(
        credentialIssuer: credentialIssuer,
        client: client,
        verifyJws: verifyJws,
      ),
      isNull,
    );
    expect(verifications, isEmpty);
  });

  test('rejects a JWS whose signature does not verify', () async {
    verdict = false;
    stubResponse(jws());

    expect(
      await resolveVeranaSignedIssuerMetadata(
        credentialIssuer: credentialIssuer,
        client: client,
        verifyJws: verifyJws,
      ),
      isNull,
    );
    expect(verifications, hasLength(1));
  });

  test('fails closed when the metadata endpoint errors', () async {
    when(
      () => client.get(any(), headers: any(named: 'headers')),
    ).thenThrow(Exception('network down'));

    expect(
      await resolveVeranaSignedIssuerMetadata(
        credentialIssuer: credentialIssuer,
        client: client,
        verifyJws: verifyJws,
      ),
      isNull,
    );
  });

  test('strips a trailing slash before fetching and matching', () async {
    stubResponse(jws());

    final signedIssuer = await resolveVeranaSignedIssuerMetadata(
      credentialIssuer: '$credentialIssuer/',
      client: client,
      verifyJws: verifyJws,
    );

    expect(signedIssuer, isNotNull);
  });
}
