import 'dart:async';

import 'package:altme/app/app.dart';
import 'package:altme/dashboard/json_viewer/view/json_viewer_page.dart';
import 'package:altme/dashboard/profile/cubit/profile_cubit.dart';
import 'package:altme/dashboard/qr_code/qr_code_scan/cubit/qr_code_scan_cubit.dart';
import 'package:altme/dashboard/qr_code/widget/developer_mode_dialog.dart';
import 'package:altme/l10n/l10n.dart';
import 'package:altme/oidc4vc/helper_function/get_payload.dart';
import 'package:altme/oidc4vc/helper_function/oidc4vp_prompt.dart';
import 'package:altme/oidc4vc/model/verified_request_context.dart';
import 'package:altme/oidc4vp_transaction/widget/accept_oidc4_vp_transaction_page.dart';
import 'package:altme/scan/cubit/scan_cubit.dart';
import 'package:altme/trusted_list/function/check_presentation_is_trusted.dart';
import 'package:altme/trusted_list/function/check_verana_trust.dart';
import 'package:altme/trusted_list/function/is_certificate_valid.dart';
import 'package:altme/trusted_list/model/trusted_entity.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:jwt_decode/jwt_decode.dart';

Future<void> oidc4vpSiopV2AcceptHost({
  required Uri uri,
  required BuildContext context,
  required bool isDeveloperMode,
  required DioClient client,
  required bool showPrompt,
  required Issuer approvedIssuer,
  required VerifiedRequestContext? verifiedRequest,
}) async {
  final l10n = context.l10n;
  final processingUri = verifiedRequest?.bindToUri(uri) ?? uri;

  final String? requestUri = processingUri.queryParameters['request_uri'];
  final String? request = processingUri.queryParameters['request'];
  String? encodedRequest;
  Map<String, dynamic>? requestPayload;

  if (verifiedRequest != null) {
    encodedRequest = verifiedRequest.encodedRequest;
    requestPayload = verifiedRequest.payload;
  } else if (requestUri != null || request != null) {
    encodedRequest = await getPayload(client, requestUri, request) as String?;
    requestPayload = decodePayload(
      jwtDecode: JWTDecode(),
      token: encodedRequest!,
    );
  }

  if (isDeveloperMode) {
    late String formattedData;

    late String url;

    if (requestPayload != null) {
      final clientId =
          requestPayload['client_id']?.toString() ??
          getClientIdForPresentation(
            processingUri.queryParameters['client_id'],
          );

      url = getUpdatedUrlForSIOPV2OIC4VP(
        uri: processingUri,
        response: requestPayload,
        clientId: clientId.toString(),
      );
      formattedData = await getFormattedStringOIDC4VPSIOPV2FromRequest(
        url: url,
        client: client,
        response: requestPayload,
      );
    } else if (processingUri.queryParameters['presentation_definition'] !=
            null ||
        processingUri.queryParameters['presentation_definition_uri'] != null) {
      final Map<String, dynamic>? presentationDefinition =
          await getPresentationDefinition(uri: processingUri, client: client);
      final Map<String, dynamic>? clientMetaData = await getClientMetada(
        client: client,
        uri: processingUri,
      );
      formattedData = getFormattedStringOIDC4VPSIOPV2(
        '',
        processingUri.queryParameters,
        clientMetaData,
        presentationDefinition,
      );
    } else {
      throw Exception('Invalid Presentation Request');
    }

    LoadingView().hide();
    final bool moveAhead =
        await showDialog<bool>(
          context: context,
          builder: (_) {
            return DeveloperModeDialog(
              uri: processingUri,
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
  final profile = context.read<ProfileCubit>().state.model;
  final trustedListEnabled =
      profile.profileSetting.walletSecurityOptions.trustedList;
  final trustedList = profile.trustedList;
  TrustedEntity? trustedEntity;
  if (trustedListEnabled && verifiedRequest != null) {
    try {
      if (trustedList == null) {
        throw Exception('Missing trusted list.');
      }

      final clientId = getVerifierClientIdFromVerifiedRequest(verifiedRequest);
      trustedEntity = getStaticVerifierFromVerifiedRequest(
        trustedList: trustedList,
        verifiedRequest: verifiedRequest,
      );
      if (trustedEntity != null) {
        checkPresentationIsTrusted(
          trustedEntity: trustedEntity,
          encodedPresentation: verifiedRequest.encodedRequest,
        );
        isCertificateValid(
          trustedEntity: trustedEntity,
          signedMetadata: verifiedRequest.encodedRequest,
        );
        // issuer has passed the trusted list checks
      } else if (clientId != null) {
        // Fall back to live Verana resolution for DID-identified verifiers.
        // Verana vouches for the entity itself, so the x509/vcType checks above
        // (which model the static ETSI-style list) do not apply to this path.
        trustedEntity = await getEntityFromVerana(
          verifiedRequest: verifiedRequest,
          type: TrustedEntityType.verifier,
          client: client,
        );
      }
    } catch (e) {
      context.read<QRCodeScanCubit>().emitError(error: e);
      return;
    }
  }
  if (requestPayload != null) {
    if (requestPayload.containsKey('transaction_data')) {
      LoadingView().hide();
      unawaited(
        context.read<ScanCubit>().addTransactionData(
          requestPayload['transaction_data'] as List<dynamic>,
        ),
      );

      await Navigator.of(context).push<void>(
        AcceptOidc4VpTransactionPage.route(
          trustedListEnabled: trustedListEnabled,
          trustedEntity: trustedEntity,
          uri: processingUri,
          showPrompt: showPrompt,
          client: client,
        ),
      );
      LoadingView().hide();
      return;
    }
  }
  await Oidc4VpPrompt(
    context: context,
    l10n: l10n,
    trustedListEnabled: trustedListEnabled,
    trustedEntity: trustedEntity,
    uri: processingUri,
    client: client,
    showPrompt: showPrompt,
  ).show();

  // Default action if there is no prompt

  LoadingView().hide();
}
