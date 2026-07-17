import 'dart:async';

import 'package:altme/app/shared/constants/parameters.dart';
import 'package:altme/app/shared/dio_client/dio_client.dart';
import 'package:altme/trusted_list/model/trusted_entity.dart';
import 'package:altme/trusted_list/model/verana_trust.dart';
import 'package:altme/trusted_list/widget/verana_trust_details_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDioClient extends Mock implements DioClient {}

void main() {
  const did = 'did:webvh:verifier.example';

  final entity = VeranaTrustedEntity(
    id: did,
    type: TrustedEntityType.verifier,
    vcTypes: const <String>['urn:example:credential'],
    resolution: const VeranaTrustResolution(
      did: did,
      trustStatus: VeranaTrustStatus.trusted,
      production: true,
      evaluatedAt: '2026-07-17T09:00:00Z',
      expiresAt: '2026-07-18T09:00:00Z',
      evaluatedAtBlock: 4380399,
    ),
  );

  VeranaTrustDetails details() => const VeranaTrustDetails(
    did: did,
    trustStatus: VeranaTrustStatus.trusted,
    production: true,
    evaluatedAt: '2026-07-17T09:00:00Z',
    expiresAt: '2026-07-18T09:00:00Z',
    evaluatedAtBlock: 4380399,
    credentials: <VeranaTrustCredential>[
      VeranaTrustCredential(
        ecsType: 'ECS-SERVICE',
        result: 'VALID',
        issuedBy: 'did:webvh:issuer.example',
        claims: <String, dynamic>{
          'name': 'Verifier service',
          'type': 'identity-verifier',
          'description': 'Checks an identity credential.',
          'privacyPolicy': 'https://example.com/privacy',
          'termsAndConditions': 'https://example.com/terms',
          'unexpected': 'must not render',
        },
      ),
      VeranaTrustCredential(
        ecsType: 'ECS-ORG',
        result: 'VALID',
        claims: <String, dynamic>{
          'name': 'Verifier organization',
          'address': '1 Trust Street',
          'registryId': 'FR-12345',
          'countryCode': 'FR',
        },
      ),
    ],
  );

  Widget page(VeranaDetailsLoader loader, {ThemeData? theme}) => MaterialApp(
    theme: theme,
    home: VeranaTrustDetailsPage(
      entity: entity,
      client: _MockDioClient(),
      detailsLoader: loader,
    ),
  );

  testWidgets('renders summary immediately then allowlisted credentials', (
    WidgetTester tester,
  ) async {
    final completer = Completer<VeranaTrustDetails?>();
    await tester.pumpWidget(page(() => completer.future));

    expect(find.text('Trusted'), findsOneWidget);
    expect(find.text(did), findsOneWidget);
    expect(find.text('2026-07-17T09:00:00Z'), findsOneWidget);
    expect(find.text('2026-07-18T09:00:00Z'), findsOneWidget);
    expect(find.text('4380399'), findsOneWidget);
    expect(find.byKey(const Key('verana-details-loading')), findsOneWidget);

    completer.complete(details());
    await tester.pumpAndSettle();

    expect(find.text('Verifier service'), findsOneWidget);
    expect(find.text('identity-verifier'), findsOneWidget);
    expect(find.text('Verifier organization'), findsOneWidget);
    expect(find.text('did:webvh:issuer.example'), findsOneWidget);
    expect(find.text('Credential issuer'), findsOneWidget);
    expect(find.text('Verana resolver'), findsOneWidget);
    expect(find.text(Parameters.veranaResolverUrl), findsOneWidget);
    expect(find.text('must not render'), findsNothing);
  });

  testWidgets('uses dark secondary text on the trusted summary card', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      page(() async => details(), theme: ThemeData.dark()),
    );
    await tester.pumpAndSettle();

    final didLabel = tester.widget<Text>(find.text('DID'));
    final didValue = tester.widget<SelectableText>(
      find.widgetWithText(SelectableText, did),
    );

    expect(didLabel.style?.color, Colors.black87);
    expect(didValue.style?.color, Colors.black87);
  });

  testWidgets('retries when detailed trust evidence is unavailable', (
    WidgetTester tester,
  ) async {
    var loaderCalls = 0;
    await tester.pumpWidget(
      page(() async {
        loaderCalls++;
        return null;
      }),
    );
    await tester.pumpAndSettle();

    expect(find.text('Detailed trust evidence unavailable'), findsOneWidget);
    expect(loaderCalls, 1);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(loaderCalls, 2);
  });

  testWidgets(
    'excludes invalid and indeterminate credentials from trust evidence',
    (WidgetTester tester) async {
      const invalidService = 'Invalid service must not render';
      const missingResultOrganization = 'Missing result must not render';
      const unknownService = 'Unknown result must not render';

      await tester.pumpWidget(
        page(
          () async => const VeranaTrustDetails(
            did: did,
            trustStatus: VeranaTrustStatus.trusted,
            production: true,
            credentials: <VeranaTrustCredential>[
              VeranaTrustCredential(
                ecsType: 'ECS-SERVICE',
                result: 'VALID',
                claims: <String, dynamic>{'name': 'Valid service'},
              ),
              VeranaTrustCredential(
                ecsType: 'ECS-SERVICE',
                result: 'INVALID',
                claims: <String, dynamic>{'name': invalidService},
              ),
              VeranaTrustCredential(
                ecsType: 'ECS-ORG',
                claims: <String, dynamic>{'name': missingResultOrganization},
              ),
              VeranaTrustCredential(
                ecsType: 'ECS-SERVICE',
                result: 'UNKNOWN',
                claims: <String, dynamic>{'name': unknownService},
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Valid service'), findsOneWidget);
      expect(find.text(invalidService), findsNothing);
      expect(find.text(missingResultOrganization), findsNothing);
      expect(find.text(unknownService), findsNothing);
    },
  );
}
