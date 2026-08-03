import 'dart:async';

import 'package:altme/app/shared/dio_client/dio_client.dart';
import 'package:altme/app/shared/widget/button/my_elevated_button.dart';
import 'package:altme/app/shared/widget/button/my_outlined_button.dart';
import 'package:altme/oidc4vc/widget/verana_consent_dialog.dart';
import 'package:altme/trusted_list/function/verana_permissions.dart';
import 'package:altme/trusted_list/model/verana_trust.dart';
import 'package:altme/trusted_list/widget/verana_trust_chain_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockDioClient extends Mock implements DioClient {}

const did = 'did:webvh:QmT4vPz:service.example';

VeranaConsentTrust consent(VeranaTrustStatus? trustStatus) =>
    VeranaConsentTrust(
      did: did,
      details: trustStatus == null
          ? null
          : VeranaTrustDetails(
              did: did,
              trustStatus: trustStatus,
              production: false,
              credentials: const <VeranaTrustCredential>[],
            ),
    );

VeranaAccreditationChecker checker(Future<VeranaAccreditationCheck> result) =>
    ({
      required String did,
      required VeranaPermissionRole role,
      required DioClient client,
      String? vct,
    }) => result;

Widget dialog({
  required VeranaConsentTrust trust,
  required VeranaAccreditationChecker checkAccreditation,
  bool invertedCallToAction = false,
}) => MaterialApp(
  home: VeranaConsentDialog(
    title: 'Do you trust this host?',
    consent: trust,
    kind: VeranaAskKind.offer,
    client: MockDioClient(),
    yesLabel: 'Allow',
    noLabel: 'Deny',
    vct: 'vpr:verana:testnet/cs/v1/js/7',
    invertedCallToAction: invertedCallToAction,
    checkAccreditation: checkAccreditation,
  ),
);

GestureTapCallback? allowOnPressed(WidgetTester tester) {
  final widget = tester.widget(find.byKey(const Key('verana-consent-allow')));
  if (widget is MyElevatedButton) return widget.onPressed;
  return (widget as MyOutlinedButton).onPressed;
}

void main() {
  const grantedCheck = VeranaAccreditationCheck(
    granted: true,
    reason: 'An active issuer permission covers this schema',
  );
  const refusedCheck = VeranaAccreditationCheck(
    granted: false,
    reason: 'No issuer permission for this schema',
  );
  const undeterminedCheck = VeranaAccreditationCheck(
    granted: null,
    reason:
        'The Verana registry could not be reached, so this permission could '
        'not be checked',
  );

  testWidgets('disables accept while the check is in flight', (tester) async {
    final completer = Completer<VeranaAccreditationCheck>();
    await tester.pumpWidget(
      dialog(
        trust: consent(VeranaTrustStatus.trusted),
        checkAccreditation: checker(completer.future),
      ),
    );

    expect(allowOnPressed(tester), isNull);
    expect(find.text('Checking the Verana public registry…'), findsOneWidget);

    completer.complete(grantedCheck);
    await tester.pumpAndSettle();

    expect(allowOnPressed(tester), isNotNull);
  });

  testWidgets('disables accept when the registry refused the permission', (
    tester,
  ) async {
    await tester.pumpWidget(
      dialog(
        trust: consent(VeranaTrustStatus.trusted),
        checkAccreditation: checker(Future.value(refusedCheck)),
      ),
    );
    await tester.pumpAndSettle();

    expect(allowOnPressed(tester), isNull);
    expect(find.textContaining('is not an authorized issuer'), findsOneWidget);
  });

  testWidgets('disables accept for an UNTRUSTED verdict even when granted', (
    tester,
  ) async {
    await tester.pumpWidget(
      dialog(
        trust: consent(VeranaTrustStatus.untrusted),
        invertedCallToAction: true,
        checkAccreditation: checker(Future.value(grantedCheck)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('UNTRUSTED'), findsOneWidget);
    expect(allowOnPressed(tester), isNull);
  });

  testWidgets('keeps accept enabled on could-not-determine', (tester) async {
    await tester.pumpWidget(
      dialog(
        trust: consent(VeranaTrustStatus.trusted),
        checkAccreditation: checker(Future.value(undeterminedCheck)),
      ),
    );
    await tester.pumpAndSettle();

    expect(allowOnPressed(tester), isNotNull);
  });

  testWidgets(
    'keeps accept enabled when the resolver could not be reached at all',
    (tester) async {
      await tester.pumpWidget(
        dialog(
          trust: consent(null),
          invertedCallToAction: true,
          checkAccreditation: checker(Future.value(undeterminedCheck)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('COULD NOT VERIFY'), findsOneWidget);
      expect(allowOnPressed(tester), isNotNull);
    },
  );

  testWidgets('treats a throwing checker as could-not-determine', (
    tester,
  ) async {
    await tester.pumpWidget(
      dialog(
        trust: consent(VeranaTrustStatus.trusted),
        checkAccreditation:
            ({
              required String did,
              required VeranaPermissionRole role,
              required DioClient client,
              String? vct,
            }) => Future<VeranaAccreditationCheck>.error(
              Exception('checker crashed'),
            ),
      ),
    );
    await tester.pumpAndSettle();

    expect(allowOnPressed(tester), isNotNull);
    expect(find.byKey(const Key('verana-ask-block')), findsOneWidget);
  });

  testWidgets('pops true only through the enabled accept action', (
    tester,
  ) async {
    await tester.pumpWidget(
      dialog(
        trust: consent(VeranaTrustStatus.trusted),
        checkAccreditation: checker(Future.value(grantedCheck)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('is an authorized issuer'), findsOneWidget);
    expect(allowOnPressed(tester), isNotNull);
  });
}
