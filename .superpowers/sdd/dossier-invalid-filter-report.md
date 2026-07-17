# Dossier invalid evidence filter

## Finding

`parseVeranaTrustDetails` preserved each credential's `result`, but
`VeranaTrustDetailsPage` previously rendered every known `ECS-SERVICE` and
`ECS-ORG` credential. An `INVALID`, missing, or unrecognized result could
therefore appear as positive trust evidence in the green dossier flow.

## Change

`VeranaTrustCredential.isValid` is true only when `result == 'VALID'`.
The positive evidence filter now requires both that valid result and a known
ECS type. Non-valid evidence is excluded rather than shown in a positive card.
The existing `VALID` service, organization, issuer, and resolver attribution
remain unchanged.

## Coverage

- Model coverage verifies `INVALID`, missing, and unknown results are not valid.
- Widget coverage verifies only the valid service renders; invalid, missing, and
  unknown-result service/organization claims do not render.

## Verification

- `flutter test test/trusted_list/model/verana_trust_test.dart test/trusted_list/widget/verana_trust_details_page_test.dart` passed: 12 tests.
- `dart format --set-exit-if-changed` passed for the two implementation and two test files.
- Narrow `flutter analyze` passed with no issues.
- `git diff --check` passed.

GitNexus impact lookup was attempted before editing, but the installed index
cannot parse Dart on this machine and does not contain the dossier symbols.
