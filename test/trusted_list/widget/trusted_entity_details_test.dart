import 'package:altme/app/shared/dio_client/dio_client.dart';
import 'package:altme/oidc4vp_transaction/widget/accept_oidc4_vp_transaction_page.dart';
import 'package:altme/trusted_list/model/trusted_entity.dart';
import 'package:altme/trusted_list/model/verana_trust.dart';
import 'package:altme/trusted_list/widget/trusted_entity_details.dart';
import 'package:altme/trusted_list/widget/verana_trust_details_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDioClient extends Mock implements DioClient {}

void main() {
  const did = 'did:webvh:verifier.example';

  final veranaEntity = VeranaTrustedEntity(
    id: did,
    type: TrustedEntityType.verifier,
    vcTypes: const <String>['urn:example:credential'],
    resolution: const VeranaTrustResolution(
      did: did,
      trustStatus: VeranaTrustStatus.trusted,
      production: true,
      evaluatedAtBlock: 4380399,
    ),
  );

  testWidgets('renders a Verana trust card and opens its dossier', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TrustedEntityDetails(
          trustedEntity: veranaEntity,
          client: _MockDioClient(),
        ),
      ),
    );

    expect(find.byKey(const Key('verana-trust-card')), findsOneWidget);
    expect(find.text('TRUSTED'), findsOneWidget);
    expect(find.text('TESTNET'), findsOneWidget);

    await tester.tap(find.byKey(const Key('verana-trust-card')));
    await tester.pumpAndSettle();

    expect(find.byType(VeranaTrustDetailsPage), findsOneWidget);
  });

  testWidgets('keeps static trusted entity rendering unchanged', (
    WidgetTester tester,
  ) async {
    final entity = TrustedEntity(
      id: 'did:webvh:static.example',
      type: TrustedEntityType.verifier,
      vcTypes: const <String>['urn:example:credential'],
      name: 'Static verifier',
      description: 'Static trusted-list description',
    );

    await tester.pumpWidget(
      MaterialApp(home: TrustedEntityDetails(trustedEntity: entity)),
    );

    expect(find.text('Static verifier'), findsOneWidget);
    expect(find.text('Static trusted-list description'), findsOneWidget);
    expect(find.byKey(const Key('verana-trust-card')), findsNothing);
  });

  testWidgets('transaction display opens Verana trust details', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DisplayEntity(
          trustedEntity: veranaEntity,
          notTrustedText: 'Untrusted verifier',
          trustedListEnabled: true,
          uri: Uri.parse('https://verifier.example/authorize'),
          client: _MockDioClient(),
        ),
      ),
    );

    expect(find.byKey(const Key('verana-trust-card')), findsOneWidget);

    await tester.tap(find.byKey(const Key('verana-trust-card')));
    await tester.pumpAndSettle();

    expect(find.byType(VeranaTrustDetailsPage), findsOneWidget);
  });
}
