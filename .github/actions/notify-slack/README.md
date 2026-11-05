# notify-slack

Posts, updates or replies to a Slack message as the Merlin bot (shown as `MAGE CI`). It wraps [`slackapi/slack-github-action`](https://github.com/slackapi/slack-github-action) v4: a small bash and `jq` step builds the payload, then slackapi sends it. The inputs and outputs are the same as before the wrap. The action never fails the calling job: Slack errors become `::warning::` lines.

Keep this directory byte-identical across the MAGE repos. See `.github/AGENTS.md`.

## Inputs

| Input | Default | Notes |
| --- | --- | --- |
| `token` | `''` | Bot token. Pass `${{ secrets.SLACK_BOT_TOKEN }}`; a composite action cannot read secrets itself. Empty skips with a notice. |
| `channel` | `C08HFEC8W9W` | #mobile-app-growth-alerts |
| `status` | `info` | `pending` ⏳, `success` ✅, `failure` ❌, `stopped` ⏹️, `warning` ⚠️, `info` ℹ️ |
| `title` | required | Bold headline after the emoji. |
| `body` | `''` | mrkdwn, multi-line allowed. |
| `fields` | `''` | Lines of `Label: value`, shown as plain-text fields (max 10). |
| `links` | `''` | Lines of `Label\|URL`. A `Run` link to the current run is always appended. |
| `ts` | `''` | Update this message (`chat.update`) instead of posting. |
| `thread_ts` | `''` | Post as a reply in this message's thread. Ignored when `ts` is set. |
| `mention` | `''` | Raw Slack mention text, e.g. `<@U123>`, placed at the start of the text. |
| `username` | `$SLACK_USERNAME`, else `MAGE CI` | Needs `chat:write.customize`. Applies to new posts only. |
| `icon_emoji` | `$SLACK_ICON_EMOJI`, else `:crystal_ball:` | Applies to new posts only. |

## Outputs

| Output | Notes |
| --- | --- |
| `ts` | ts of the posted or updated message. Falls back to the `ts` input when skipped or failed. |
| `channel` | Channel ID from Slack's response. Falls back to the `channel` input when skipped or failed. |

Set `SLACK_USERNAME` and `SLACK_ICON_EMOJI` in a workflow `env:` block to give every call in that repo its own bot name and avatar without repeating the inputs.

Retries are handled by slackapi (up to 5 attempts, honouring `Retry-After`).

## Examples

Post and keep the ts:

```yaml
- id: slack
  uses: ./.github/actions/notify-slack
  with:
    token: ${{ secrets.SLACK_BOT_TOKEN }}
    status: pending
    title: Android SDK 4.5.2 awaiting approval
    fields: |
      Commit: abc1234
      Requested by: ${{ github.actor }}
    links: Draft release|https://github.com/org/repo/releases/tag/4.5.2
# steps.slack.outputs.ts
```

Update that message later:

```yaml
- uses: ./.github/actions/notify-slack
  with:
    token: ${{ secrets.SLACK_BOT_TOKEN }}
    ts: ${{ needs.prepare.outputs.slack_ts }}
    status: success
    title: Android SDK 4.5.2 published
```

Reply in its thread:

```yaml
- uses: ./.github/actions/notify-slack
  with:
    token: ${{ secrets.SLACK_BOT_TOKEN }}
    thread_ts: ${{ needs.prepare.outputs.slack_ts }}
    status: failure
    title: JitPack build failed
    body: Check the build log.
```
