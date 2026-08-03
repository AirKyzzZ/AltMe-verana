import 'package:altme/app/app.dart';
import 'package:altme/dashboard/json_viewer/view/json_viewer_page.dart';
import 'package:altme/dashboard/profile/cubit/profile_cubit.dart';
import 'package:altme/dashboard/qr_code/qr_code_scan/cubit/qr_code_scan_cubit.dart';
import 'package:altme/dashboard/qr_code/widget/developer_mode_dialog.dart';
import 'package:altme/l10n/l10n.dart';
import 'package:altme/oidc4vc/helper_function/get_offered_vct_for_accreditation.dart';
import 'package:altme/oidc4vc/helper_function/verana_signed_issuer_metadata.dart';
import 'package:altme/oidc4vc/widget/verana_consent_dialog.dart';
import 'package:altme/trusted_list/function/check_issuer_is_trusted.dart';
import 'package:altme/trusted_list/function/check_verana_trust.dart';
import 'package:altme/trusted_list/model/verana_trust.dart';
import 'package:altme/trusted_list/widget/verana_trust_chain_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:oidc4vc/oidc4vc.dart';

Future<void> oidc4vciAcceptHost({
  required Oidc4vcParameters oidc4vcParameters,
  required BuildContext context,
  required bool isDeveloperMode,
  required DioClient client,
  required bool showPrompt,
  required Issuer approvedIssuer,
}) async {
  final l10n = context.l10n;
  var acceptHost = true;
  final issuanceParameters = oidc4vcParameters;

  if (isDeveloperMode) {
    /// issuance case
    final formattedData = getFormattedStringOIDC4VCI(
      url: oidc4vcParameters.initialUri.toString(),
      oidc4vcParameters: oidc4vcParameters,
    );

    LoadingView().hide();
    final bool moveAhead =
        await showDialog<bool>(
          context: context,
          builder: (_) {
            return DeveloperModeDialog(
              uri: oidc4vcParameters.initialUri,
              onDisplay: () async {
                final returnedValue = await Navigator.of(context).push<dynamic>(
                  JsonViewerPage.route(
                    title: l10n.display,
                    data: formattedData,
                  ),
                );

                if (returnedValue != null &&
                    returnedValue is bool &&
                    returnedValue) {
                  Navigator.of(context).pop(true);
                }
                return;
              },
              onSkip: () {
                Navigator.of(context).pop(true);
              },
            );
          },
        ) ??
        true;
    if (!moveAhead) return;
  }

  /// if dev mode is ON show some dialog to show data
  await handleErrorForOidc4Vci(
    oidc4vcParameters: oidc4vcParameters,
    didKeyType: context
        .read<ProfileCubit>()
        .state
        .model
        .profileSetting
        .selfSovereignIdentityOptions
        .customOidc4vcProfile
        .defaultDid,
    clientType: context
        .read<ProfileCubit>()
        .state
        .model
        .profileSetting
        .selfSovereignIdentityOptions
        .customOidc4vcProfile
        .clientType,
  );
  final profile = context.read<ProfileCubit>().state.model;
  final trustedListEnabled =
      profile.profileSetting.walletSecurityOptions.trustedList;
  final trustedList = profile.trustedList;
  if (trustedListEnabled) {
    try {
      if (trustedList == null) {
        throw Exception('Missing trusted list.');
      }
      // issuer open id configuration from signed metadata is used instead of
      // unsigned open id configuration

      final issuerOpenIdConfiguration =
          oidc4vcParameters.issuerOpenIdConfiguration;

      final trustedEntity = getIssuerFromTrustedList(
        issuerOpenIdConfiguration: issuerOpenIdConfiguration,
        trustedList: trustedList,
      );
      if (trustedEntity != null) {
        throw UnsupportedError(
          'Signed issuer metadata cryptographic verification is unavailable',
        );
      } else {
        // An issuer proves a DID only by DID-signing its metadata; an
        // unsigned or x509-signed issuer never reaches the Verana path and
        // keeps the plain untrusted warning below.
        final signedIssuer = await resolveVeranaSignedIssuerMetadata(
          credentialIssuer: oidc4vcParameters.issuer,
          client: client,
        );
        if (signedIssuer != null) {
          final veranaConsent = await getVeranaConsentTrust(
            did: signedIssuer.did,
            client: client,
          );
          final trusted =
              veranaConsent.trustStatus == VeranaTrustStatus.trusted;
          LoadingView().hide();
          acceptHost =
              await showDialog<bool>(
                context: context,
                builder: (BuildContext context) {
                  return VeranaConsentDialog(
                    title: l10n.scanPromptHost,
                    subtitle: trusted ? null : l10n.notTrustedEntity,
                    invertedCallToAction: !trusted,
                    consent: veranaConsent,
                    kind: VeranaAskKind.offer,
                    vct: getOfferedVctForAccreditation(oidc4vcParameters),
                    client: client,
                    yesLabel: l10n.communicationHostAllow,
                    noLabel: l10n.communicationHostDeny,
                  );
                },
              ) ??
              false;
        } else {
          LoadingView().hide();
          acceptHost =
              await showDialog<bool>(
                context: context,
                builder: (BuildContext context) {
                  return ConfirmDialog(
                    title: l10n.scanPromptHost,
                    subtitle: l10n.notTrustedEntity,
                    yes: l10n.communicationHostAllow,
                    no: l10n.communicationHostDeny,
                    invertedCallToAction: true,
                  );
                },
              ) ??
              false;
        }
      }
    } catch (e) {
      context.read<QRCodeScanCubit>().emitError(error: e);
      return;
    }
  }
  if (showPrompt && !trustedListEnabled) {
    /// OIDC4VCI Case

    final String title = l10n.scanPromptHost;

    String subtitle = (approvedIssuer.did.isEmpty)
        ? oidc4vcParameters.initialUri.host
        : '''${approvedIssuer.organizationInfo.legalName}\n${approvedIssuer.organizationInfo.currentAddress}''';

    subtitle = await getHost(uri: oidc4vcParameters.initialUri, client: client);

    LoadingView().hide();
    acceptHost =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            return ConfirmDialog(
              title: title,
              subtitle: subtitle,
              yes: l10n.communicationHostAllow,
              no: l10n.communicationHostDeny,
              //lock: state.uri!.scheme == 'http',
            );
          },
        ) ??
        false;
  }
  LoadingView().hide();
  if (acceptHost) {
    await context.read<QRCodeScanCubit>().acceptOidc4vci(
      approvedIssuer: approvedIssuer,
      oidc4vcParameters: issuanceParameters,
      qrCodeScanCubit: context.read<QRCodeScanCubit>(),
    );
  } else {
    context.read<QRCodeScanCubit>().emitError(
      error: ResponseMessage(
        message: ResponseString.RESPONSE_STRING_SCAN_REFUSE_HOST,
      ),
    );
    return;
  }
}
