#!/usr/bin/env bash
# Static contract tests for delivery-owner no-mistakes validation runs.
set -u

# shellcheck source=tests/lib.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

validate_contract() {
  awk '
    /^### Validate$/ { found = 1; next }
    found && /^### / { exit }
    found { print }
  ' "$ROOT/AGENTS.md"
}

test_delivery_unit_has_one_gate_owner() {
  local contract
  contract=$(validate_contract)

  assert_contains "$contract" 'define the complete delivery unit and name exactly one delivery-owner task' \
    "Validate contract does not require one named owner for the delivery unit"
  assert_contains "$contract" 'Implementation lanes self-review their scoped diff, run targeted tests, commit, and report completion' \
    "Validate contract does not require lane self-validation"
  assert_contains "$contract" 'they never invoke `no-mistakes` independently' \
    "Validate contract permits lane-local no-mistakes runs"
  assert_contains "$contract" 'Only after that report may Firstmate explicitly steer the delivery owner to invoke one end-of-delivery `no-mistakes` gate' \
    "Validate contract does not reserve one end gate for an explicit Firstmate steer"
  assert_contains "$contract" 'Secondmates use this same contract inside their isolated homes because they are Firstmates' \
    "Validate contract does not apply unchanged inside secondmate homes"
  pass "Validate contract assigns one end gate to the named delivery owner"
}

test_owner_owns_synchronous_driver() {
  local contract
  contract=$(validate_contract)

  assert_contains "$contract" 'The delivery owner that starts the one no-mistakes run drives the pipeline' \
    "Validate contract does not assign the run to its delivery owner"
  assert_contains "$contract" "owns every \`no-mistakes axi run\` and \`no-mistakes axi respond\` call through the next gate or outcome" \
    "Validate contract does not assign every synchronous driver call to the delivery owner"
  assert_contains "$contract" 'process every synchronous return until completion or a genuinely new escalation' \
    "Validate contract does not require the delivery owner to process every synchronous return"
  pass "Validate contract assigns the complete synchronous driver loop to the delivery owner"
}

test_firstmate_never_responds_for_crew_run() {
  local contract
  contract=$(validate_contract)

  assert_contains "$contract" "Firstmate never invokes \`no-mistakes axi respond\` for a crew-owned run." \
    "Validate contract permits Firstmate to respond directly for a crew-owned run"
  pass "Validate contract forbids Firstmate from responding directly for a crew-owned run"
}

test_firstmate_bounds_fix_rounds() {
  local contract
  contract=$(validate_contract)

  assert_contains "$contract" 'Firstmate owns the decision on every finding' \
    "Validate contract does not assign every finding decision to Firstmate"
  assert_contains "$contract" 'never blindly authorizes recursive review-fix rounds' \
    "Validate contract does not forbid blind recursive fix authorization"
  assert_contains "$contract" 'one contained fix round' \
    "Validate contract does not bound the authorized fix round"
  assert_contains "$contract" 'new material defect, the owner parks the run and returns the finding to Firstmate' \
    "Validate contract does not park new material defects after the contained fix round"
  pass "Validate contract gives Firstmate every finding decision and bounds fix rounds"
}

test_delivery_unit_has_one_gate_owner
test_owner_owns_synchronous_driver
test_firstmate_never_responds_for_crew_run
test_firstmate_bounds_fix_rounds
