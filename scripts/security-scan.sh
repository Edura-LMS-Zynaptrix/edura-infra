#!/usr/bin/env bash
# Dependency vulnerability scan for edura-infra (development guideline 7.2).
#
# Audits every requirements file with pip-audit and fails on any known
# vulnerability that is not listed in security/accepted-vulnerabilities.txt.
# Accepted advisories are reported but do not fail the build; dependencies are
# never changed by this script. See docs/SECURITY-SCAN.md.
set -uo pipefail

ACCEPTED_FILE="security/accepted-vulnerabilities.txt"
REQUIREMENTS=(rabbitmq/requirements.txt rabbitmq/tests/requirements-test.txt)

ignore_args=()
while read -r id _; do
  [[ -z "${id}" || "${id}" == \#* ]] && continue
  ignore_args+=(--ignore-vuln "${id}")
  echo "Accepted advisory (not failing the build): ${id}"
done < "${ACCEPTED_FILE}"

status=0
for req in "${REQUIREMENTS[@]}"; do
  echo "::group::pip-audit ${req}"
  pip-audit -r "${req}" "${ignore_args[@]}" || status=1
  echo "::endgroup::"
done

if [[ "${status}" -ne 0 ]]; then
  echo "::error::Unaccepted vulnerabilities found. Fix them, or add the advisory ID and a reason to ${ACCEPTED_FILE} (see docs/SECURITY-SCAN.md)."
fi
exit "${status}"
