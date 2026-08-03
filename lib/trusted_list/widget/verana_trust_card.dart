import 'package:altme/app/shared/dio_client/dio_client.dart';
import 'package:altme/trusted_list/model/verana_trust.dart';
import 'package:altme/trusted_list/widget/verana_trust_chain_view.dart';
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
    final credentials = resolution is VeranaTrustDetails
        ? resolution.credentials
        : const <VeranaTrustCredential>[];

    return VeranaTrustChainView(
      key: const Key('verana-trust-card'),
      did: entity.id,
      verdict: resolution.trustStatus,
      credentials: credentials,
      onTap: () async {
        await Navigator.of(
          context,
        ).push(VeranaTrustDetailsPage.route(entity: entity, client: client));
      },
    );
  }
}
