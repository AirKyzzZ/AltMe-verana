import 'package:altme/app/app.dart';
import 'package:altme/trusted_list/function/verana_ecs.dart';
import 'package:altme/trusted_list/function/verana_permissions.dart';
import 'package:altme/trusted_list/model/verana_trust.dart';
import 'package:altme/trusted_list/widget/verana_trust_chain_view.dart';
import 'package:flutter/material.dart';

typedef VeranaAccreditationChecker =
    Future<VeranaAccreditationCheck> Function({
      required String did,
      required VeranaPermissionRole role,
      required DioClient client,
      String? vct,
    });

/// The consent dialog for a DID-identified counterparty: the shared trust
/// card, with the accept action gated on the evaluation. Accept is disabled
/// while the accreditation check is in flight, when the identity verdict is
/// UNTRUSTED, and when the registry positively refused the permission -
/// could-not-determine never disables.
class VeranaConsentDialog extends StatefulWidget {
  const VeranaConsentDialog({
    super.key,
    required this.title,
    required this.consent,
    required this.kind,
    required this.client,
    required this.yesLabel,
    required this.noLabel,
    this.vct,
    this.subtitle,
    this.invertedCallToAction = false,
    this.checkAccreditation = checkVeranaAccreditation,
  });

  final String title;
  final VeranaConsentTrust consent;
  final VeranaAskKind kind;
  final DioClient client;
  final String yesLabel;
  final String noLabel;
  final String? vct;
  final String? subtitle;
  final bool invertedCallToAction;
  final VeranaAccreditationChecker checkAccreditation;

  @override
  State<VeranaConsentDialog> createState() => _VeranaConsentDialogState();
}

class _VeranaConsentDialogState extends State<VeranaConsentDialog> {
  VeranaAccreditationCheck? _accreditation;
  var _checking = true;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final check = await widget.checkAccreditation(
      did: widget.consent.did,
      role: widget.kind == VeranaAskKind.offer
          ? VeranaPermissionRole.issuer
          : VeranaPermissionRole.verifier,
      client: widget.client,
      vct: widget.vct,
    );
    if (!mounted) return;
    setState(() {
      _accreditation = check;
      _checking = false;
    });
  }

  bool get _accreditationBlocks => _accreditation?.granted == false;

  bool get _acceptDisabled =>
      _checking ||
      _accreditationBlocks ||
      widget.consent.trustStatus == VeranaTrustStatus.untrusted;

  VeranaTrustAsk get _ask {
    final credentials =
        widget.consent.details?.credentials ?? const <VeranaTrustCredential>[];
    final party =
        readEcsService(findServiceCredential(credentials))?.name ??
        readEcsOrganization(findOrganizationCredential(credentials))?.name ??
        veranaMiddleTruncate(widget.consent.did);
    return VeranaTrustAsk(
      kind: widget.kind,
      granted: _checking ? null : _accreditation?.granted,
      party: party,
      credential:
          _accreditation?.credentialName ?? widget.vct ?? 'this credential',
      reason: _checking
          ? 'Checking the Verana public registry…'
          : _accreditation?.reason,
    );
  }

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).colorScheme.onSurface;

    final yesButton = widget.invertedCallToAction
        ? MyOutlinedButton(
            key: const Key('verana-consent-allow'),
            text: widget.yesLabel,
            verticalSpacing: 14,
            fontSize: 15,
            elevation: 0,
            onPressed: _acceptDisabled
                ? null
                : () => Navigator.of(context).pop(true),
          )
        : MyElevatedButton(
            key: const Key('verana-consent-allow'),
            text: widget.yesLabel,
            verticalSpacing: 14,
            fontSize: 15,
            elevation: 0,
            onPressed: _acceptDisabled
                ? null
                : () => Navigator.of(context).pop(true),
          );
    final noButton = widget.invertedCallToAction
        ? MyElevatedButton(
            text: widget.noLabel,
            verticalSpacing: 14,
            fontSize: 15,
            elevation: 0,
            onPressed: () => Navigator.of(context).pop(false),
          )
        : MyOutlinedButton(
            text: widget.noLabel,
            verticalSpacing: 14,
            fontSize: 15,
            elevation: 0,
            onPressed: () => Navigator.of(context).pop(false),
          );

    return SafeArea(
      child: AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        surfaceTintColor: Colors.transparent,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 15,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(25)),
        ),
        content: SizedBox(
          width: MediaQuery.of(context).size.shortestSide * 0.85,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.title,
                style: Theme.of(
                  context,
                ).textTheme.headlineMedium!.copyWith(color: textColor),
                textAlign: TextAlign.center,
              ),
              if (widget.subtitle != null) ...[
                const SizedBox(height: Sizes.spaceSmall),
                Text(
                  widget.subtitle!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium!.copyWith(color: textColor),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: Sizes.spaceSmall),
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.55,
                  ),
                  child: SingleChildScrollView(
                    child: VeranaTrustChainView(
                      did: widget.consent.did,
                      verdict: widget.consent.trustStatus,
                      credentials:
                          widget.consent.details?.credentials ??
                          const <VeranaTrustCredential>[],
                      ask: _ask,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(child: noButton),
                  const SizedBox(width: 16),
                  Expanded(child: yesButton),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
