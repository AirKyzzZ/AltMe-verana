import 'package:altme/app/shared/constants/parameters.dart';
import 'package:altme/app/shared/dio_client/dio_client.dart';
import 'package:altme/trusted_list/model/verana_trust.dart';
import 'package:altme/trusted_list/widget/verana_trust_details_page.dart';
import 'package:flutter/material.dart';

class VeranaTrustCard extends StatelessWidget {
  const VeranaTrustCard({
    super.key,
    required this.entity,
    required this.client,
  });

  final VeranaTrustedEntity entity;
  final DioClient client;

  @override
  Widget build(BuildContext context) {
    final resolution = entity.resolution;
    final block = resolution.evaluatedAtBlock;
    final summary = <String>[
      _trustStatusLabel(resolution.trustStatus),
      if (Parameters.veranaNetworkProduction) 'Production' else 'TESTNET',
      if (block != null) 'Block $block',
    ].join(' · ');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('verana-trust-card'),
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          await Navigator.of(
            context,
          ).push(VeranaTrustDetailsPage.route(entity: entity, client: client));
        },
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(Icons.verified_rounded, color: Colors.green.shade700),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Verified by Verana Trust Registry',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.green.shade900,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(summary),
                    const SizedBox(height: 4),
                    const Text('Tap to inspect trust chain'),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

String _trustStatusLabel(VeranaTrustStatus status) => switch (status) {
  VeranaTrustStatus.trusted => 'Trusted',
  VeranaTrustStatus.partial => 'Partial',
  VeranaTrustStatus.untrusted => 'Untrusted',
};
