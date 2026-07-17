import 'dart:async';
import 'dart:convert';

import 'package:altme/app/app.dart';
import 'package:altme/dashboard/dashboard.dart';
import 'package:altme/l10n/l10n.dart';
import 'package:altme/oidc4vc/helper_function/oidc4vci_accept_host.dart';
import 'package:altme/trusted_list/model/trusted_entity.dart';
import 'package:altme/trusted_list/model/trusted_list.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:oidc4vc/oidc4vc.dart';

class _MockProfileCubit extends MockCubit<ProfileState>
    implements ProfileCubit {}

class _MockQRCodeScanCubit extends MockCubit<QRCodeScanState>
    implements QRCodeScanCubit {}

class _MockDioClient extends Mock implements DioClient {}

const _issuer = 'https://unfold-org.example/oid4vci/unfold';
const _configurationId = 'unfold-attestation';
const _vct = 'https://unfold-org.example/vct/unfold-attestation';

String _forgedSignedMetadata() {
  String encodeSegment(Map<String, dynamic> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');

  final header = encodeSegment(const <String, dynamic>{
    'alg': 'none',
    'typ': 'openidvci-issuer-metadata+jwt',
    'x5c': <String>['trusted-root'],
  });
  final payload = encodeSegment(const <String, dynamic>{
    'iat': 1784332800,
    'iss': 'https://attacker.example',
    'sub': _issuer,
    'credential_issuer': _issuer,
    'token_endpoint': 'https://attacker.example/token',
    'nonce_endpoint': 'https://attacker.example/nonce',
    'credential_endpoint': 'https://attacker.example/credential',
    'credential_configurations_supported': <String, dynamic>{
      _configurationId: <String, dynamic>{'format': 'dc+sd-jwt', 'vct': _vct},
    },
  });
  return '$header.$payload.';
}

OpenIdConfiguration _issuerMetadata({String? signedMetadata}) =>
    OpenIdConfiguration(
      requirePushedAuthorizationRequests: false,
      credentialIssuer: _issuer,
      tokenEndpoint: '$_issuer/token',
      nonceEndpoint: '$_issuer/nonce',
      credentialEndpoint: '$_issuer/credential',
      signedMetadata: signedMetadata,
      credentialConfigurationsSupported: const <String, dynamic>{
        _configurationId: <String, dynamic>{
          'format': 'dc+sd-jwt',
          'cryptographic_binding_methods_supported': <String>['jwk'],
          'credential_signing_alg_values_supported': <String>['ES256'],
          'proof_types_supported': <String, dynamic>{
            'jwt': <String, dynamic>{
              'proof_signing_alg_values_supported': <String>['ES256'],
            },
          },
          'vct': _vct,
        },
      },
    );

Oidc4vcParameters _parameters(OpenIdConfiguration metadata) =>
    Oidc4vcParameters(
      oidc4vciDraftType: OIDC4VCIDraftType.draft13,
      useOAuthAuthorizationServerLink: false,
      initialUri: Uri.parse(
        'openid-credential-offer://?credential_offer_uri='
        'https%3A%2F%2Funfold-org.example%2Foffers%2Fredacted',
      ),
      userPinRequired: false,
      issuerState: null,
      issuer: _issuer,
      tokenEndpoint: '$_issuer/token',
      credentialOffer: const <String, dynamic>{
        'credential_issuer': _issuer,
        'credential_configuration_ids': <String>[_configurationId],
      },
      issuerOpenIdConfiguration: metadata,
    );

ProfileState _profileState({required bool issuerIsListed}) {
  final base = ProfileModel.empty();
  final entities = <TrustedEntity>[
    if (issuerIsListed)
      TrustedEntity(
        id: _issuer,
        type: TrustedEntityType.issuer,
        rootCertificates: const <String>['trusted-root'],
        vcTypes: const <String>[_vct],
      ),
  ];

  return ProfileState(
    model: base.copyWith(
      profileSetting: base.profileSetting.copyWith(
        walletSecurityOptions: base.profileSetting.walletSecurityOptions
            .copyWith(trustedList: true),
      ),
      trustedList: TrustedList(
        ecosystem: 'test',
        lastUpdated: '2026-07-18',
        entities: entities,
      ),
    ),
  );
}

class _TestHarness extends StatelessWidget {
  const _TestHarness({required this.parameters, required this.client});

  final Oidc4vcParameters parameters;
  final DioClient client;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () {
            unawaited(
              oidc4vciAcceptHost(
                oidc4vcParameters: parameters,
                context: context,
                isDeveloperMode: false,
                client: client,
                showPrompt: true,
                approvedIssuer: Issuer.emptyIssuer('unfold-org.example'),
              ),
            );
          },
          child: const Text('Start issuance'),
        ),
      ),
    );
  }
}

void main() {
  late _MockProfileCubit profileCubit;
  late _MockQRCodeScanCubit qrCodeScanCubit;
  late _MockDioClient client;

  setUp(() {
    profileCubit = _MockProfileCubit();
    qrCodeScanCubit = _MockQRCodeScanCubit();
    client = _MockDioClient();
  });

  Future<void> pumpHarness(
    WidgetTester tester, {
    required bool issuerIsListed,
    String? signedMetadata,
  }) async {
    when(
      () => profileCubit.state,
    ).thenReturn(_profileState(issuerIsListed: issuerIsListed));

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: <BlocProvider<dynamic>>[
          BlocProvider<ProfileCubit>.value(value: profileCubit),
          BlocProvider<QRCodeScanCubit>.value(value: qrCodeScanCubit),
        ],
        child: MaterialApp(
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: _TestHarness(
            parameters: _parameters(
              _issuerMetadata(signedMetadata: signedMetadata),
            ),
            client: client,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Start issuance'));
    await tester.pumpAndSettle();
  }

  testWidgets('unsigned unlisted issuer reaches prominent untrusted consent', (
    WidgetTester tester,
  ) async {
    await pumpHarness(tester, issuerIsListed: false);

    expect(find.byType(ConfirmDialog), findsOneWidget);
    expect(
      find.text(
        'This entity is not in the trusted list. '
        'You should be very cautious with untrusted entities.',
      ),
      findsOneWidget,
    );
    verifyNever(
      () => qrCodeScanCubit.emitError(error: any<dynamic>(named: 'error')),
    );
  });

  testWidgets('unsigned listed issuer fails closed', (
    WidgetTester tester,
  ) async {
    await pumpHarness(tester, issuerIsListed: true);

    expect(find.byType(ConfirmDialog), findsNothing);
    final captured = verify(
      () =>
          qrCodeScanCubit.emitError(error: captureAny<dynamic>(named: 'error')),
    ).captured.single;
    expect(
      captured.toString(),
      contains(
        'Signed issuer metadata cryptographic verification is unavailable',
      ),
    );
  });

  testWidgets('invalid signed metadata for listed issuer fails closed', (
    WidgetTester tester,
  ) async {
    await pumpHarness(
      tester,
      issuerIsListed: true,
      signedMetadata: 'not-a-jwt',
    );

    expect(find.byType(ConfirmDialog), findsNothing);
    verify(
      () => qrCodeScanCubit.emitError(error: any<dynamic>(named: 'error')),
    ).called(1);
  });

  testWidgets(
    'forged signed metadata cannot replace listed issuer configuration',
    (WidgetTester tester) async {
      await pumpHarness(
        tester,
        issuerIsListed: true,
        signedMetadata: _forgedSignedMetadata(),
      );

      expect(find.byType(ConfirmDialog), findsNothing);
      final captured = verify(
        () => qrCodeScanCubit.emitError(
          error: captureAny<dynamic>(named: 'error'),
        ),
      ).captured.single;
      expect(
        captured.toString(),
        contains(
          'Signed issuer metadata cryptographic verification is unavailable',
        ),
      );
    },
  );
}
