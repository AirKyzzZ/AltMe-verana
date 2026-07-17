import 'package:altme/app/app.dart';
import 'package:altme/oidc4vc/helper_function/add_oidc4vc_credential.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('extractIssuedCredential', () {
    const encodedCredential = 'header.payload.signature~disclosure~';

    test('accepts a single Draft 15 credential response', () {
      expect(
        extractIssuedCredential(const <String, dynamic>{
          'credential': encodedCredential,
        }),
        encodedCredential,
      );
    });

    test('accepts a V1 batch credential response', () {
      expect(
        extractIssuedCredential(const <String, dynamic>{
          'credentials': <dynamic>[
            <String, dynamic>{'credential': encodedCredential},
          ],
        }),
        encodedCredential,
      );
    });

    test('rejects a response without an encoded credential', () {
      expect(
        () => extractIssuedCredential(const <String, dynamic>{
          'credentials': <dynamic>[],
        }),
        throwsA(
          isA<ResponseMessage>().having(
            (message) => message.data,
            'data',
            const <String, dynamic>{
              'error': 'invalid_format',
              'error_description': 'The format of vc is incorrect.',
            },
          ),
        ),
      );
    });
  });
}
