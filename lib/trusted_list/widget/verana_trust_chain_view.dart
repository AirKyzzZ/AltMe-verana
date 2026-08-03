import 'package:altme/app/shared/constants/parameters.dart';
import 'package:altme/trusted_list/function/verana_ecs.dart';
import 'package:altme/trusted_list/model/verana_trust.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

// The trust-card v3 palette (playground/public/trust-card/index.html). The
// card paints itself as a light card on any theme so the same evaluation has
// the same face in every wallet.
const Color _ink = Color(0xFF111827);
const Color _body = Color(0xFF374151);
const Color _sub = Color(0xFF6B7280);
const Color _faint = Color(0xFF9CA3AF);
const Color _line = Color(0xFFE5E7EB);
const Color _card = Color(0xFFFFFFFF);
const Color _chip = Color(0xFFF3F4F6);
const Color _ok = Color(0xFF059669);
const Color _okSoft = Color(0xFFECFDF5);
const Color _okRail = Color(0xFF6EE7B7);
const Color _warn = Color(0xFFD97706);
const Color _warnLine = Color(0xFFFDE68A);
const Color _bad = Color(0xFFDC2626);
const Color _badSoft = Color(0xFFFEF2F2);
const Color _badRail = Color(0xFFFCA5A5);
const Color _noneRail = Color(0xFFD1D5DB);
const Color _brand = Color(0xFF7C3AED);
const Color _veranaPurple = Color(0xFF763EF0);

const List<Color> _logoTints = <Color>[
  Color(0xFF0F9488),
  Color(0xFF1D4ED8),
  Color(0xFF9A3412),
  Color(0xFF3F3F46),
];

enum VeranaAskKind { offer, request }

class VeranaTrustAsk {
  const VeranaTrustAsk({
    required this.kind,
    required this.party,
    required this.credential,
    this.granted,
    this.ecosystem,
    this.reason,
  });

  final VeranaAskKind kind;

  /// `null` while the check is in flight, or when it could not be determined.
  final bool? granted;
  final String party;
  final String credential;
  final String? ecosystem;
  final String? reason;
}

enum _StepTone { ok, bad, none }

/// The proof-of-trust card as versioned at
/// playground/public/trust-card/index.html: identity chain first, verdict
/// second, conditions third. Shared verbatim by the consent surfaces and the
/// banner so a wallet never shows two different faces of the same evaluation.
class VeranaTrustChainView extends StatelessWidget {
  const VeranaTrustChainView({
    super.key,
    required this.did,
    required this.verdict,
    required this.credentials,
    this.isLoading = false,
    this.ask,
    this.onTap,
  });

  final String did;

  /// `null` means the resolver could not be reached: could-not-verify, which
  /// is not a verdict.
  final VeranaTrustStatus? verdict;
  final List<VeranaTrustCredential> credentials;
  final bool isLoading;
  final VeranaTrustAsk? ask;
  final VoidCallback? onTap;

  Color get _tone => switch (verdict) {
    VeranaTrustStatus.trusted => _ok,
    VeranaTrustStatus.partial => _warn,
    VeranaTrustStatus.untrusted => _bad,
    null => _faint,
  };

  String get _verdictLabel => switch (verdict) {
    VeranaTrustStatus.trusted => 'TRUSTED',
    VeranaTrustStatus.partial => 'PARTIAL',
    VeranaTrustStatus.untrusted => 'UNTRUSTED',
    null => 'COULD NOT VERIFY',
  };

  _StepTone _rowTone(VeranaTrustCredential? credential) {
    if (verdict == null) return _StepTone.none;
    if (verdict == VeranaTrustStatus.untrusted) return _StepTone.bad;
    return credential?.isValid ?? false ? _StepTone.ok : _StepTone.bad;
  }

  /// A credential can be structurally VALID and still verify nothing: the
  /// untrusted demo services issue their ECS credentials to themselves. A
  /// green tick there would be a trust signal the resolver never gave, so the
  /// tick follows the resolution and self-issued claims are withheld rather
  /// than shown as facts.
  bool _selfIssued(VeranaTrustCredential? credential) {
    final issuedBy = credential?.issuedBy;
    return issuedBy != null && issuedBy.split('#').first == did;
  }

  String? _withheld(VeranaTrustCredential? credential, _StepTone tone) {
    if (tone == _StepTone.none) return 'Not checked.';
    if (credential == null) return null;
    return _selfIssued(credential)
        ? 'Issued by this service to itself, so nothing independent '
              'verifies it.'
        : 'Nothing in the registry vouches for this credential, so its '
              'claims are not shown.';
  }

  @override
  Widget build(BuildContext context) {
    final serviceCredential = findServiceCredential(credentials);
    final organizationCredential = findOrganizationCredential(credentials);
    final serviceTone = _rowTone(serviceCredential);
    final organizationTone = _rowTone(organizationCredential);
    final service = serviceTone == _StepTone.ok
        ? readEcsService(serviceCredential)
        : null;
    final organization = organizationTone == _StepTone.ok
        ? readEcsOrganization(organizationCredential)
        : null;
    final description = stripLinks(service?.description);
    final minimumAge = service?.minimumAgeRequired ?? 0;
    final hasConditions =
        service != null &&
        (service.terms != null || service.privacy != null || minimumAge > 0);
    final note = verdict == null
        ? 'The Verana resolver could not be reached. This counterparty is '
              'neither trusted nor untrusted.'
        : credentials.isNotEmpty
        ? describeVerdict(verdict!, credentials)
        : null;

    final card = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _line),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(fontSize: 14, color: _ink, height: 1.4),
        child: Column(
          key: const Key('verana-trust-chain'),
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _DidRow(did: did, tone: _tone),
            const SizedBox(height: 14),
            if (isLoading) ...[
              const Text(
                'Resolving trust credentials…',
                style: TextStyle(color: _sub, fontSize: 13),
              ),
              const SizedBox(height: 12),
            ],
            if (credentials.isNotEmpty) ...[
              _ChainStep(
                tone: serviceTone,
                label: 'Service',
                child: service != null
                    ? _ServiceIdentity(
                        service: service,
                        description: description,
                      )
                    : _FailedIdentity(
                        tone: serviceTone,
                        title: serviceCredential != null
                            ? 'Service claims not verified'
                            : 'No ECS-Service credential presented',
                        detail: _withheld(serviceCredential, serviceTone),
                      ),
              ),
              _ChainStep(
                tone: organizationTone,
                label: 'Operated by',
                isLast: true,
                child: organization != null
                    ? _OrganizationIdentity(organization: organization)
                    : _FailedIdentity(
                        tone: organizationTone,
                        title: organizationCredential != null
                            ? 'Operator claims not verified'
                            : 'No ECS-Organization credential presented',
                        detail:
                            _withheld(
                              organizationCredential,
                              organizationTone,
                            ) ??
                            'Nothing verifies who operates this service',
                      ),
              ),
              const SizedBox(height: 14),
            ],
            _VerdictPill(label: _verdictLabel, tone: _tone, note: note),
            if (ask != null) ...[
              const SizedBox(height: 14),
              _AskBlock(ask: ask!),
            ],
            if (hasConditions) ...[
              const SizedBox(height: 14),
              _Conditions(service: service),
            ],
          ],
        ),
      ),
    );

    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: card,
      ),
    );
  }
}

String veranaMiddleTruncate(String value, {int head = 26, int tail = 12}) =>
    value.length <= head + tail + 1
    ? value
    : '${value.substring(0, head)}…${value.substring(value.length - tail)}';

class _DidRow extends StatelessWidget {
  const _DidRow({required this.did, required this.tone});

  final String did;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            veranaMiddleTruncate(did),
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: const TextStyle(color: _sub, fontSize: 12.5),
          ),
        ),
        if (!Parameters.veranaNetworkProduction) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              border: Border.all(color: _warnLine, width: 1.5),
              borderRadius: BorderRadius.circular(7),
            ),
            child: const Text(
              'TESTNET',
              style: TextStyle(
                color: _warn,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
        const SizedBox(width: 8),
        const VeranaMark(size: 19),
      ],
    );
  }
}

class _ChainStep extends StatelessWidget {
  const _ChainStep({
    required this.tone,
    required this.label,
    required this.child,
    this.isLast = false,
  });

  final _StepTone tone;
  final String label;
  final Widget child;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final rail = switch (tone) {
      _StepTone.ok => _okRail,
      _StepTone.bad => _badRail,
      _StepTone.none => _noneRail,
    };
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                _StepTick(tone: tone),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      decoration: BoxDecoration(
                        color: rail,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SectionLabel(label),
                  const SizedBox(height: 4),
                  child,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepTick extends StatelessWidget {
  const _StepTick({required this.tone});

  final _StepTone tone;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      _StepTone.ok => _ok,
      _StepTone.bad => _bad,
      _StepTone.none => _faint,
    };
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: tone == _StepTone.none
          ? const Text(
              '?',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            )
          : Icon(
              tone == _StepTone.ok ? Icons.check : Icons.close,
              size: 15,
              color: Colors.white,
            ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: _sub,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _ServiceIdentity extends StatelessWidget {
  const _ServiceIdentity({required this.service, required this.description});

  final VeranaEcsService service;
  final VeranaStrippedText description;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LogoBadge(name: service.name, verified: service.logo?.digest != null),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _IdentityHeading(name: service.name),
              if (description.text.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(description.text, style: const TextStyle(color: _body)),
              ],
              if (description.removed > 0) ...[
                const SizedBox(height: 4),
                Text(
                  '${description.removed} '
                  'link${description.removed > 1 ? 's' : ''} removed from '
                  'this description before display',
                  style: const TextStyle(color: _faint, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _OrganizationIdentity extends StatelessWidget {
  const _OrganizationIdentity({required this.organization});

  final VeranaEcsOrganization organization;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LogoBadge(
          name: organization.name,
          verified: organization.logo?.digest != null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _IdentityHeading(
                name: organization.name,
                countryCode: organization.countryCode,
              ),
              if (organization.address != null) ...[
                const SizedBox(height: 2),
                Text(
                  organization.address!,
                  style: const TextStyle(color: _body),
                ),
              ],
              if (organization.registryId != null) ...[
                const SizedBox(height: 6),
                _RegistryChip(label: 'REG', value: organization.registryId!),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _FailedIdentity extends StatelessWidget {
  const _FailedIdentity({required this.tone, required this.title, this.detail});

  final _StepTone tone;
  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: TextStyle(
            color: tone == _StepTone.none ? _sub : _bad,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (detail != null) ...[
          const SizedBox(height: 2),
          Text(detail!, style: const TextStyle(color: _faint, fontSize: 12)),
        ],
      ],
    );
  }
}

class _IdentityHeading extends StatelessWidget {
  const _IdentityHeading({this.name, this.countryCode});

  final String? name;
  final String? countryCode;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          name ?? 'Not presented',
          style: const TextStyle(
            color: _ink,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (countryCode != null) _CountryFlag(code: countryCode!),
      ],
    );
  }
}

class _RegistryChip extends StatelessWidget {
  const _RegistryChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _chip,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _sub,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _body,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VerdictPill extends StatelessWidget {
  const _VerdictPill({required this.label, required this.tone, this.note});

  final String label;
  final Color tone;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final noteColor = tone == _ok || tone == _faint ? _sub : _bad;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          key: const Key('verana-verdict-pill'),
          padding: const EdgeInsets.fromLTRB(8, 6, 14, 6),
          decoration: BoxDecoration(
            color: _card,
            border: Border.all(color: tone, width: 2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const VeranaMark(size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tone,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (note != null) ...[
          const SizedBox(height: 8),
          Text(note!, style: TextStyle(color: noteColor, fontSize: 13)),
        ],
      ],
    );
  }
}

class _AskBlock extends StatelessWidget {
  const _AskBlock({required this.ask});

  final VeranaTrustAsk ask;

  @override
  Widget build(BuildContext context) {
    final granted = ask.granted;
    final borderColor = granted == null
        ? _line
        : granted
        ? _ok
        : _bad;
    final background = granted == null
        ? const Color(0xFFF9FAFB)
        : granted
        ? _okSoft
        : _badSoft;
    final verb = ask.kind == VeranaAskKind.offer
        ? 'authorized issuer'
        : 'authorized verifier';
    final sentence = granted == null
        ? (ask.reason ?? 'This could not be checked against the registry.')
        : '${ask.party} is ${granted ? 'an' : 'not an'} $verb of '
              '${ask.credential}'
              '${ask.ecosystem != null ? ' in ${ask.ecosystem}' : ''}';

    return Container(
      key: const Key('verana-ask-block'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: borderColor, width: 1.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _SectionLabel(
            ask.kind == VeranaAskKind.offer ? 'Offers you' : 'Asks you for',
          ),
          const SizedBox(height: 6),
          Text(
            ask.credential,
            style: const TextStyle(
              color: _ink,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                granted == null
                    ? Icons.info_outline
                    : granted
                    ? Icons.check
                    : Icons.close,
                size: 18,
                color: granted == null
                    ? _sub
                    : granted
                    ? _ok
                    : _bad,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  sentence,
                  style: const TextStyle(color: Color(0xFF1F2937)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Conditions extends StatelessWidget {
  const _Conditions({required this.service});

  final VeranaEcsService? service;

  @override
  Widget build(BuildContext context) {
    final minimumAge = service?.minimumAgeRequired ?? 0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _chip,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const _SectionLabel('Conditions of connecting'),
          const SizedBox(height: 10),
          if (minimumAge > 0)
            Row(
              children: [
                Text(
                  '$minimumAge+',
                  style: const TextStyle(
                    color: _warn,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'This service requires you to be at least $minimumAge '
                    'to connect',
                    style: const TextStyle(color: _body, fontSize: 13),
                  ),
                ),
              ],
            )
          else
            const Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: _faint),
                SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'No age restriction',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: _body, fontSize: 13),
                  ),
                ),
              ],
            ),
          _ConditionRow(asset: service?.terms, label: 'Terms & conditions'),
          _ConditionRow(asset: service?.privacy, label: 'Privacy policy'),
        ],
      ),
    );
  }
}

class _ConditionRow extends StatelessWidget {
  const _ConditionRow({required this.asset, required this.label});

  final VeranaEcsAsset? asset;
  final String label;

  @override
  Widget build(BuildContext context) {
    final uri = veranaHttpUri(asset?.uri);
    if (asset == null || uri == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: InkWell(
        onTap: () => launchUrl(uri, mode: LaunchMode.externalApplication),
        child: Row(
          children: [
            const Icon(Icons.lock, size: 14, color: _brand),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: _brand,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (asset!.digest != null) ...[
              const Icon(Icons.check, size: 12, color: _ok),
              const SizedBox(width: 3),
              const Text(
                'intact',
                style: TextStyle(
                  color: _ok,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ] else
              const Text(
                'no digest',
                style: TextStyle(
                  color: _faint,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LogoBadge extends StatelessWidget {
  const _LogoBadge({this.name, this.verified = false});

  final String? name;
  final bool verified;

  @override
  Widget build(BuildContext context) {
    final initials = _initialsOf(name);
    final tint = _logoTints[initials.codeUnitAt(0) % _logoTints.length];
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(11),
            ),
            alignment: Alignment.center,
            child: Text(
              initials,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: initials.length > 1 ? 14 : 17,
              ),
            ),
          ),
          if (verified)
            Positioned(
              right: -4,
              bottom: -4,
              child: Container(
                width: 16,
                height: 16,
                decoration: const BoxDecoration(
                  color: _card,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.check, size: 11, color: _ok),
              ),
            ),
        ],
      ),
    );
  }
}

String _initialsOf(String? name) {
  final words = (name ?? '?')
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .take(2);
  final initials = words.map((word) => word[0].toUpperCase()).join();
  return initials.isEmpty ? '?' : initials;
}

class VeranaMark extends StatelessWidget {
  const VeranaMark({super.key, this.size = 16});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size.square(size), painter: _VeranaMarkPainter());
  }
}

class _VeranaMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 64;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(12 * scale)),
      Paint()..color = _veranaPurple,
    );

    final white = Paint()..color = Colors.white;
    final outer = Path()
      ..moveTo(46.3 * scale, 22.8 * scale)
      ..lineTo(32 * scale, 50.4 * scale)
      ..lineTo(17.7 * scale, 22.8 * scale)
      ..lineTo(19.6 * scale, 19.4 * scale)
      ..lineTo(21.6 * scale, 22.9 * scale)
      ..lineTo(32 * scale, 43.4 * scale)
      ..lineTo(42.4 * scale, 22.9 * scale)
      ..lineTo(44.4 * scale, 19.4 * scale)
      ..close();
    final inner = Path()
      ..moveTo(22.4 * scale, 15.8 * scale)
      ..lineTo(32 * scale, 34.2 * scale)
      ..lineTo(41.7 * scale, 15.8 * scale)
      ..close();
    canvas.drawPath(outer, white);
    canvas.drawPath(inner, white);
  }

  @override
  bool shouldRepaint(_VeranaMarkPainter oldDelegate) => false;
}

// Drawn rather than an emoji: emoji flags resolve through the system font and
// fall back inconsistently across Android versions, on the screen where
// someone decides whether to trust a counterparty. Undrawn countries degrade
// to the ISO code rather than to a broken glyph.
class _CountryFlag extends StatelessWidget {
  const _CountryFlag({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    if (code == 'CH') {
      return CustomPaint(
        size: const Size.square(16),
        painter: _SwissFlagPainter(),
      );
    }
    return Text(
      code,
      style: const TextStyle(
        color: _sub,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _SwissFlagPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 32;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(3 * scale)),
      Paint()..color = const Color(0xFFD52B1E),
    );
    final white = Paint()..color = Colors.white;
    canvas.drawRect(
      Rect.fromLTWH(13 * scale, 6 * scale, 6 * scale, 20 * scale),
      white,
    );
    canvas.drawRect(
      Rect.fromLTWH(6 * scale, 13 * scale, 20 * scale, 6 * scale),
      white,
    );
  }

  @override
  bool shouldRepaint(_SwissFlagPainter oldDelegate) => false;
}
