#!/bin/bash
# The installer signature check (verify_installer, require_signer) with
# osslsigncode's report stubbed, so every branch runs without a real
# certificate: a good signer, the wrong signer, a broken signature, and the
# revocation-list fallback.
set -uo pipefail

# shellcheck source=tests/unit/lib.sh
source /unit/lib.sh
load_entrypoint

readonly GOOD_REPORT="Signer's certificate:
	Signer #0:
		Subject: /C=CY/ST=Lemesos/O=MetaQuotes Ltd./CN=MetaQuotes Ltd.
		Issuer : /C=GB/O=Sectigo Limited/CN=Sectigo Public Code Signing CA E36
Succeeded"
# "MetaQuotes" appears in the OU and in a later certificate, never in the
# signer's CN, so the check must refuse it.
readonly WRONG_SIGNER_REPORT="Signer's certificate:
	Signer #0:
		Subject: /C=XX/O=Evil/OU=MetaQuotes/CN=Evil Corp
	Signer #1:
		Subject: /C=CY/O=MetaQuotes Ltd./CN=MetaQuotes Ltd.
Succeeded"
readonly CRL_REPORT="Failed to download CRL from http://crl.example.invalid/ca.crl"
readonly BROKEN_REPORT="Signature verification: failed
Message digest mismatch"

# verify_installer calls signature_report inside $(...), a subshell, so the
# call count and the remaining CRL failures live in files, not variables.
CALLS_FILE="$(mktemp)"
CRL_FAILURES_FILE="$(mktemp)"
readonly CALLS_FILE CRL_FAILURES_FILE
# Each scenario sets these: the report and status of the full check, how many
# full checks fail with a CRL error before one succeeds (CRL_FAILURES), and the
# report and status of the -ignore-crl check.
FULL_REPORT=""
FULL_STATUS=0
CRL_FAILURES=0
IGNORE_CRL_REPORT=""
IGNORE_CRL_STATUS=0

sleep() {
    # The retry delay; the checks need no real waiting.
    :
}

signature_report() {
    local remaining
    printf 'x' >>"$CALLS_FILE"
    if [[ " $* " == *" -ignore-crl "* ]]; then
        printf '%s\n' "$IGNORE_CRL_REPORT"
        return "$IGNORE_CRL_STATUS"
    fi
    remaining="$(cat "$CRL_FAILURES_FILE")"
    if ((remaining > 0)); then
        printf '%s' "$((remaining - 1))" >"$CRL_FAILURES_FILE"
        printf '%s\n' "$CRL_REPORT"
        return 1
    fi
    printf '%s\n' "$FULL_REPORT"
    return "$FULL_STATUS"
}

# Runs verify_installer for one scenario; sets STATUS, CALLS and LOGS.
run_check() {
    local log_file
    log_file="$(mktemp)"
    : >"$CALLS_FILE"
    printf '%s' "$CRL_FAILURES" >"$CRL_FAILURES_FILE"
    verify_installer /tmp/mt5-setup.exe 2>"$log_file"
    STATUS=$?
    CALLS="$(wc -c <"$CALLS_FILE")"
    LOGS="$(cat "$log_file")"
    rm -f "$log_file"
}

FULL_REPORT="$GOOD_REPORT" FULL_STATUS=0 CRL_FAILURES=0
run_check
expect_equal "a MetaQuotes signature is accepted" "$STATUS" 0
expect_equal "a MetaQuotes signature needs one check" "$CALLS" 1

FULL_REPORT="$WRONG_SIGNER_REPORT" FULL_STATUS=0 CRL_FAILURES=0
run_check
expect_equal "another signer is refused even with MetaQuotes elsewhere in the report" "$STATUS" 1
expect_match "the refusal names the real signer" "$LOGS" 'signer=/C=XX/O=Evil/OU=MetaQuotes/CN=Evil Corp'

FULL_REPORT="$BROKEN_REPORT" FULL_STATUS=1 CRL_FAILURES=0
run_check
expect_equal "a broken signature is refused" "$STATUS" 1
expect_equal "a broken signature is not retried" "$CALLS" 1

FULL_REPORT="$GOOD_REPORT" FULL_STATUS=0 CRL_FAILURES=1
run_check
expect_equal "a revocation-list failure is retried" "$STATUS" 0
expect_equal "the retry succeeds on the second check" "$CALLS" 2

FULL_REPORT="$GOOD_REPORT" FULL_STATUS=0 CRL_FAILURES="$SIGNATURE_ATTEMPTS"
IGNORE_CRL_REPORT="$GOOD_REPORT" IGNORE_CRL_STATUS=0
run_check
expect_equal "an unreachable revocation server falls back to -ignore-crl" "$STATUS" 0
expect_equal "the fallback comes after every retry" "$CALLS" "$((SIGNATURE_ATTEMPTS + 1))"
expect_match "the fallback logs a warning" "$LOGS" '"level":"WARN".*reason=crl_unreachable'

FULL_REPORT="$GOOD_REPORT" FULL_STATUS=0 CRL_FAILURES="$SIGNATURE_ATTEMPTS"
IGNORE_CRL_REPORT="$BROKEN_REPORT" IGNORE_CRL_STATUS=1
run_check
expect_equal "the fallback still refuses a broken signature" "$STATUS" 1

FULL_REPORT="$GOOD_REPORT" FULL_STATUS=0 CRL_FAILURES="$SIGNATURE_ATTEMPTS"
IGNORE_CRL_REPORT="$WRONG_SIGNER_REPORT" IGNORE_CRL_STATUS=0
run_check
expect_equal "the fallback still refuses another signer" "$STATUS" 1
