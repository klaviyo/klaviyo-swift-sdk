#!/usr/bin/env bash
# Builds the Slack API payload for slackapi/slack-github-action.
#
# Env: SLACK_TOKEN CHANNEL STATUS TITLE BODY FIELDS LINKS TS THREAD_TS MENTION USERNAME
#      ICON_EMOJI RUN_URL RUNNER_TEMP.
# USERNAME and ICON_EMOJI fall back to SLACK_USERNAME and SLACK_ICON_EMOJI (set them in a workflow
# `env:` block), then to MAGE CI and :crystal_ball:.
# Writes skip, method and payload_path to $GITHUB_OUTPUT. When skip is true it also writes ts and
# channel, falling back to the inputs.
# Always exits 0.

set -uo pipefail

CHANNEL=${CHANNEL:-C08HFEC8W9W}
STATUS=${STATUS:-info}
USERNAME=${USERNAME:-${SLACK_USERNAME:-MAGE CI}}
ICON_EMOJI=${ICON_EMOJI:-${SLACK_ICON_EMOJI:-:crystal_ball:}}

emit() {
  [ -n "${GITHUB_OUTPUT:-}" ] || return 0
  printf '%s\n' "$@" >> "$GITHUB_OUTPUT"
}

skip() {
  emit "skip=true" "ts=${TS:-}" "channel=$CHANNEL"
  exit 0
}

if [ -z "${SLACK_TOKEN:-}" ]; then
  echo "::notice::Slack token is empty; skipping Slack notification."
  skip
fi

case "$STATUS" in
  pending) emoji="⏳" ;;
  success) emoji="✅" ;;
  failure) emoji="❌" ;;
  stopped) emoji="⏹️" ;;
  warning) emoji="⚠️" ;;
  info) emoji="ℹ️" ;;
  *)
    echo "::warning::Unknown Slack status '$STATUS'; using info."
    emoji="ℹ️"
    ;;
esac

if [ -n "${TS:-}" ]; then
  method=chat.update
else
  method=chat.postMessage
fi

payload_dir="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/slack-payload.XXXXXX")"
payload="$payload_dir/payload.json"

if ! jq -n \
  --arg channel "$CHANNEL" \
  --arg emoji "$emoji" \
  --arg title "${TITLE:-}" \
  --arg body "${BODY:-}" \
  --arg fields "${FIELDS:-}" \
  --arg links "${LINKS:-}" \
  --arg run_url "${RUN_URL:-}" \
  --arg ts "${TS:-}" \
  --arg thread_ts "${THREAD_TS:-}" \
  --arg mention "${MENTION:-}" \
  --arg username "$USERNAME" \
  --arg icon_emoji "$ICON_EMOJI" \
  '
  def esc: gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;");
  def trim: sub("^\\s+"; "") | sub("\\s+$"; "");
  def lines: split("\n") | map(gsub("\r"; "")) | map(select(test("\\S")));

  ($mention | trim) as $m
  | (if $m == "" then "" else $m + " " end) as $prefix
  | ($title | esc) as $t
  | ($fields | lines | map(
      if test(":")
      then capture("^(?<k>[^:]*):(?<v>.*)$") | {type: "mrkdwn", text: ("*" + (.k | trim | esc) + ":*\n" + (.v | trim | esc) | .[:2000])}
      else {type: "mrkdwn", text: (esc | .[:2000])}
      end
    ) | .[:10]) as $f
  | (($links | lines | map(select(contains("|")) | capture("^(?<l>[^|]*)\\|(?<u>.*)$") | {l: (.l | trim), u: (.u | trim)})
      | map(select(.u != "") | "<" + (.u | esc | gsub("\\|"; "%7C")) + "|" + (.l | esc) + ">"))
     + (if $run_url == "" then [] else ["<" + ($run_url | esc) + "|Run>"] end)) as $l
  | {
      channel: $channel,
      text: ($prefix + $emoji + " " + $t),
      blocks: (
        [{type: "section", text: {type: "mrkdwn", text: ($prefix + $emoji + " *" + $t + "*")}}]
        + (if ($body | test("\\S")) then [{type: "section", text: {type: "mrkdwn", text: ($body | .[:3000])}}] else [] end)
        + (if ($f | length) > 0 then [{type: "section", fields: $f}] else [] end)
        + (if ($l | length) > 0 then [{type: "context", elements: [{type: "mrkdwn", text: ($l | join("  ·  "))}]}] else [] end)
      ),
      unfurl_links: false,
      unfurl_media: false
    }
  + (if $ts != "" then {ts: $ts}
     else {username: $username, icon_emoji: $icon_emoji}
          + (if $thread_ts != "" then {thread_ts: $thread_ts} else {} end)
     end)
  ' > "$payload"; then
  echo "::warning::Could not build the Slack payload; no notification sent."
  skip
fi

emit "skip=false" "method=$method" "payload_path=$payload"
