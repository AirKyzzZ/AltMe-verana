import 'package:altme/trusted_list/function/verana_ecs.dart';
import 'package:altme/trusted_list/model/verana_trust.dart';
import 'package:flutter_test/flutter_test.dart';

VeranaTrustCredential credential({
  String ecsType = 'ECS-SERVICE',
  String result = 'VALID',
  String? issuedBy,
  Map<String, dynamic> claims = const <String, dynamic>{},
}) => VeranaTrustCredential(
  ecsType: ecsType,
  result: result,
  issuedBy: issuedBy,
  claims: claims,
);

void main() {
  group('readEcsService', () {
    test('reads v4 claim names with digests', () {
      final service = readEcsService(
        credential(
          claims: <String, dynamic>{
            'name': 'Vesta Organization Trust Anchor',
            'description': 'The service publishing credentials.',
            'descriptionFormat': 'text/markdown',
            'minimumAgeRequired': 16,
            'logoUri': 'https://vesta.example/logo.png',
            'logoDigestSri': 'sha384-abc',
            'termsAndConditionsUri': 'https://vesta.example/terms',
            'termsAndConditionsDigestSri': 'sha384-oqVuATXR',
            'privacyPolicyUri': 'https://vesta.example/privacy',
            'privacyPolicyDigestSri': 'sha384-Kd91mLpQ',
          },
        ),
      );

      expect(service, isNotNull);
      expect(service!.name, 'Vesta Organization Trust Anchor');
      expect(service.descriptionFormat, 'text/markdown');
      expect(service.minimumAgeRequired, 16);
      expect(service.logo?.digest, 'sha384-abc');
      expect(service.terms?.uri, 'https://vesta.example/terms');
      expect(service.terms?.digest, 'sha384-oqVuATXR');
      expect(service.privacy?.digest, 'sha384-Kd91mLpQ');
    });

    test('reads v3 claim names, with no logo digest at all', () {
      final service = readEcsService(
        credential(
          claims: <String, dynamic>{
            'name': 'Gaia Registry',
            'logo': 'https://gaia.example/logo.png',
            'termsAndConditions': 'https://gaia.example/terms',
            'termsAndConditionsHash': 'abc123',
            'privacyPolicy': 'https://gaia.example/privacy',
          },
        ),
      );

      expect(service, isNotNull);
      expect(service!.descriptionFormat, 'text/plain');
      expect(service.logo?.uri, 'https://gaia.example/logo.png');
      expect(service.logo?.digest, isNull);
      expect(service.terms?.uri, 'https://gaia.example/terms');
      expect(service.terms?.digest, 'abc123');
      expect(service.privacy?.digest, isNull);
    });

    test('withholds claims from a credential the resolver did not verify', () {
      expect(
        readEcsService(
          credential(
            result: 'INVALID',
            claims: <String, dynamic>{'name': 'Rogue Service'},
          ),
        ),
        isNull,
      );
      expect(readEcsService(null), isNull);
    });
  });

  group('readEcsOrganization', () {
    test('reads the organization identity and uppercases the country', () {
      final organization = readEcsOrganization(
        credential(
          ecsType: 'ECS-ORG',
          claims: <String, dynamic>{
            'name': 'Vesta Appliances SA',
            'countryCode': 'ch',
            'address': 'Rue du Rhône 14, 1204 Geneva',
            'registryId': 'CHE-123.456.789',
            'lei': '506700GE1G29325QX363',
          },
        ),
      );

      expect(organization, isNotNull);
      expect(organization!.countryCode, 'CH');
      expect(organization.registryId, 'CHE-123.456.789');
      expect(organization.lei, '506700GE1G29325QX363');
    });
  });

  group('deriveVerdict', () {
    final validService = credential();
    final validOrganization = credential(ecsType: 'ECS-ORG');

    test('is trusted only when both identity credentials verify', () {
      expect(
        deriveVerdict(<VeranaTrustCredential>[validService, validOrganization]),
        VeranaTrustStatus.trusted,
      );
      expect(
        deriveVerdict(<VeranaTrustCredential>[validService]),
        VeranaTrustStatus.partial,
      );
      expect(
        deriveVerdict(<VeranaTrustCredential>[
          validService,
          credential(ecsType: 'ECS-ORG', result: 'INVALID'),
        ]),
        VeranaTrustStatus.partial,
      );
      expect(
        deriveVerdict(const <VeranaTrustCredential>[]),
        VeranaTrustStatus.untrusted,
      );
      expect(deriveVerdict(null), VeranaTrustStatus.untrusted);
    });
  });

  group('describeVerdict', () {
    test('keeps the fixed cross-wallet sentences', () {
      expect(
        describeVerdict(VeranaTrustStatus.trusted, null),
        'Both identity credentials verified against the Verana public '
        'registry',
      );
      expect(
        describeVerdict(VeranaTrustStatus.untrusted, null),
        'Neither identity credential verified. This counterparty cannot '
        'present verifiable trust credentials.',
      );
      expect(
        describeVerdict(VeranaTrustStatus.untrusted, <VeranaTrustCredential>[
          credential(),
        ]),
        'The Verana public registry does not vouch for this service.',
      );
      expect(
        describeVerdict(VeranaTrustStatus.partial, <VeranaTrustCredential>[
          credential(),
        ]),
        'The service credential verified. Nothing verifies who operates it.',
      );
      expect(
        describeVerdict(VeranaTrustStatus.partial, <VeranaTrustCredential>[
          credential(ecsType: 'ECS-ORG'),
        ]),
        'The operator credential verified. Nothing verifies the service '
        'itself.',
      );
    });
  });

  group('stripLinks', () {
    test('removes markdown and bare links and counts them', () {
      final stripped = stripLinks(
        'Create your [Metaverse ID](https://evil.example) now, see '
        'https://also-evil.example for more.',
      );

      expect(stripped.text, 'Create your Metaverse ID now, see for more.');
      expect(stripped.removed, 2);
    });

    test('leaves plain text untouched', () {
      final stripped = stripLinks('Book an appliance repair.');
      expect(stripped.text, 'Book an appliance repair.');
      expect(stripped.removed, 0);
    });

    test('handles empty input', () {
      expect(stripLinks(null).text, '');
      expect(stripLinks(null).removed, 0);
    });
  });
}
