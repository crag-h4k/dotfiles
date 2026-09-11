---
description: Run local IaC + secret scanners and summarize high/critical findings (read-only)
agent: plan
---
# IaC scan

Run this project's security scanners and summarize the findings. Do NOT edit anything;
this is read-only triage.

checkov:
!`checkov -d . --compact --quiet 2>&1 | tail -60`

tfsec:
!`tfsec . --no-color --soft-fail 2>&1 | tail -60`

gitleaks:
!`gitleaks detect --no-banner --redact 2>&1 | tail -40`

actionlint:
!`actionlint -color=never 2>&1 | tail -40`

Summarize the high and critical findings, group them by file, and propose concrete
fixes. Do not modify anything; leave changes for a Build session.
