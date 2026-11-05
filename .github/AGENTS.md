# .github Guidelines

For agents and humans editing workflows and actions here. `CLAUDE.md` in this directory points to this file.

## Slack

- Use only `.github/actions/notify-slack` for Slack. It wraps slackapi/slack-github-action, so don't call slackapi or curl directly.
- `token: ${{ secrets.SLACK_BOT_TOKEN }}`. An empty token skips, so no presence checks.
- One message per pipeline run, updated through `ts` (job output or dispatch input). Failure details go in a `thread_ts` reply.
- Live status: a pipeline posts a `pending` message when it starts, edits it at a stage change, and makes a final edit (`if: success() || failure() || timed-out cancel`) to success, failure, stopped or timed out. A gate failure edits it to `blocked, <gate> failed`. Don't announce runs that were never going to deploy.
- Each workflow sets `SLACK_USERNAME` and `SLACK_ICON_EMOJI` in its top-level `env:` ("Swift SDK", `:merlin-orb-swift:`).
- `continue-on-error: true` on Slack notify steps and Slack-action checkout steps.
- Report a cancelled job only on timeout: the `Classify cancellation` step in `spm-verify.yml` and `cocoapods-publish.yml`.
- `spm-verify.yml` and `cocoapods-publish.yml` follow the live-status pattern: `slack_pending` announces (a reply in the release thread when `slack_thread_ts` is set, else top-level), one stage edit (`gates passed` / `podspecs validated`), and a final `Notify Slack` edit. `check-release-version` replies under `slack_thread_ts`, else under the announce message.
- `spm-verify.yml` dispatches the iOS test app SDK bump before it notifies Slack. A failed dispatch posts the verify result as `warning` with a "bump by hand" note and does not fail the job.
- `publish-release.yml` passes `slack_thread_ts` to `spm-verify.yml` and `cocoapods-publish.yml`, so they reply in the release thread. Release-triggered runs post fresh. Jobs in `publish-release.yml` sparse-checkout `.github/actions` into `_slack/`.
- `check-release-version` posts its mismatch alert through `notify-slack`; pass it `token` and `thread_ts`.
- `notify-slack` stays byte-identical in all 7 repos: klaviyo-android-sdk, klaviyo-android-test-app, klaviyo-swift-sdk, klaviyo-ios-test-app, klaviyo-react-native-sdk, klaviyo-expo-plugin, klaviyo-flutter-sdk.
- Backtick branches, tags, versions, commit SHAs, workflow and job names, file paths, package and secret names in titles, bodies and field values. Show 7-character SHAs with a `Commit` link.

## Workflow conventions

- Pin actions by tag. Use a full SHA with a `# vX.Y.Z` comment for actions that handle credentials or release data (`linear/linear-release-action`, `slackapi/slack-github-action`).
- `publish-release.yml` uses a `concurrency` group with `cancel-in-progress: false`.
