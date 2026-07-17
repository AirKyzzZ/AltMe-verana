import 'package:altme/app/shared/constants/parameters.dart';
import 'package:altme/app/shared/dio_client/dio_client.dart';
import 'package:altme/app/shared/widget/back_leading_button.dart';
import 'package:altme/app/shared/widget/base/background_card.dart';
import 'package:altme/app/shared/widget/base/page.dart';
import 'package:altme/trusted_list/function/check_verana_trust.dart';
import 'package:altme/trusted_list/model/verana_trust.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

typedef VeranaDetailsLoader = Future<VeranaTrustDetails?> Function();

class VeranaTrustDetailsPage extends StatefulWidget {
  const VeranaTrustDetailsPage({
    super.key,
    required this.entity,
    required this.client,
    this.detailsLoader,
  });

  final VeranaTrustedEntity entity;
  final DioClient client;
  final VeranaDetailsLoader? detailsLoader;

  static Route<void> route({
    required VeranaTrustedEntity entity,
    required DioClient client,
  }) => MaterialPageRoute<void>(
    settings: const RouteSettings(name: '/VeranaTrustDetailsPage'),
    builder: (_) => VeranaTrustDetailsPage(entity: entity, client: client),
  );

  @override
  State<VeranaTrustDetailsPage> createState() => _VeranaTrustDetailsPageState();
}

class _VeranaTrustDetailsPageState extends State<VeranaTrustDetailsPage> {
  VeranaTrustDetails? _details;
  var _isLoading = true;
  var _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _failed = false;
    });

    try {
      final details =
          await (widget.detailsLoader?.call() ??
              getVeranaTrustDetails(
                did: widget.entity.id,
                client: widget.client,
              ));
      if (!mounted) return;
      setState(() {
        _details = details;
        _isLoading = false;
        _failed = details == null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _details = null;
        _isLoading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return BasePage(
      title: 'Trust details',
      titleLeading: const BackLeadingButton(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SummaryCard(resolution: widget.entity.resolution),
          const SizedBox(height: 16),
          if (_isLoading)
            const Center(
              child: Padding(
                key: Key('verana-details-loading'),
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_failed)
            _UnavailableEvidence(onRetry: _load)
          else if (_details != null) ...[
            for (final credential in _details!.credentials)
              if (_isKnownCredential(credential)) ...[
                _CredentialCard(credential: credential),
                const SizedBox(height: 12),
              ],
            _ResolverAttribution(),
          ],
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.resolution});

  final VeranaTrustResolution resolution;

  @override
  Widget build(BuildContext context) {
    return BackgroundCard(
      color: Colors.green.shade50,
      borderRadius: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _trustStatusLabel(resolution.trustStatus),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.green.shade900,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          _SummaryField(label: 'DID', value: resolution.did),
          _SummaryField(label: 'Evaluated', value: resolution.evaluatedAt),
          _SummaryField(label: 'Expires', value: resolution.expiresAt),
          _SummaryField(
            label: 'Block',
            value: resolution.evaluatedAtBlock?.toString(),
          ),
        ],
      ),
    );
  }
}

class _SummaryField extends StatelessWidget {
  const _SummaryField({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: Colors.black87),
          ),
          SelectableText(
            value ?? 'Unavailable',
            style: DefaultTextStyle.of(
              context,
            ).style.copyWith(color: Colors.black87),
          ),
        ],
      ),
    );
  }
}

class _UnavailableEvidence extends StatelessWidget {
  const _UnavailableEvidence({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return BackgroundCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Detailed trust evidence unavailable'),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _CredentialCard extends StatelessWidget {
  const _CredentialCard({required this.credential});

  final VeranaTrustCredential credential;

  @override
  Widget build(BuildContext context) {
    final claims = credential.claims;
    final issuer = veranaDisplayString(credential.issuedBy);
    final fields = switch (credential.ecsType) {
      'ECS-SERVICE' => <_EvidenceField>[
        _EvidenceField(label: 'Name', value: claims['name']),
        _EvidenceField(label: 'Type', value: claims['type']),
        _EvidenceField(label: 'Description', value: claims['description']),
        _EvidenceField(label: 'Privacy policy', value: claims['privacyPolicy']),
        _EvidenceField(
          label: 'Terms and conditions',
          value: claims['termsAndConditions'],
        ),
      ],
      'ECS-ORG' => <_EvidenceField>[
        _EvidenceField(label: 'Name', value: claims['name']),
        _EvidenceField(label: 'Address', value: claims['address']),
        _EvidenceField(label: 'Registry ID', value: claims['registryId']),
        _EvidenceField(label: 'Country code', value: claims['countryCode']),
      ],
      _ => const <_EvidenceField>[],
    };

    return BackgroundCard(
      borderRadius: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            credential.ecsType!,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (issuer != null)
            _TextEvidence(label: 'Credential issuer', value: issuer),
          for (final field in fields) field,
        ],
      ),
    );
  }
}

class _EvidenceField extends StatelessWidget {
  const _EvidenceField({required this.label, required this.value});

  final String label;
  final dynamic value;

  @override
  Widget build(BuildContext context) {
    final text = veranaDisplayString(value);
    if (text == null) return const SizedBox.shrink();
    final uri = veranaHttpUri(value);
    if (uri == null) return _TextEvidence(label: label, value: text);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          TextButton(
            onPressed: () =>
                launchUrl(uri, mode: LaunchMode.externalApplication),
            child: Text(text),
          ),
        ],
      ),
    );
  }
}

class _TextEvidence extends StatelessWidget {
  const _TextEvidence({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          SelectableText(value),
        ],
      ),
    );
  }
}

class _ResolverAttribution extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const BackgroundCard(
      borderRadius: 16,
      child: _TextEvidence(
        label: 'Verana resolver',
        value: Parameters.veranaResolverUrl,
      ),
    );
  }
}

bool _isKnownCredential(VeranaTrustCredential credential) =>
    credential.isValid &&
    (credential.ecsType == 'ECS-SERVICE' || credential.ecsType == 'ECS-ORG');

String _trustStatusLabel(VeranaTrustStatus status) => switch (status) {
  VeranaTrustStatus.trusted => 'Trusted',
  VeranaTrustStatus.partial => 'Partial',
  VeranaTrustStatus.untrusted => 'Untrusted',
};
