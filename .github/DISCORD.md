# Discord release notifications for ShaaenFCT

The [Notify Discord on Release](workflows/discord-release.yml) GitHub Actions workflow posts a formatted Discord embed with the release version, GitHub release notes (including linked fixes/additions/commits), and a download link to the ZIP.

## One-time setup

1. Open your Discord server and choose the destination channel. Go to **Edit Channel → Integrations → Webhooks → New Webhook**. Name it `ShaaenFCT Releases`, then select **Copy Webhook URL**. Never share the full URL publicly.
2. In GitHub, open **NLshaen/ShaaenFCT → Settings → Secrets and variables → Actions → Secrets → New repository secret**.
3. Set **Name** to `DISCORD_WEBHOOK_URL` and **Secret** to the copied Discord webhook URL.

## Sending notifications

- Normal: when [Update Release changelog](workflows/release-changelog.yml) finishes successfully after a release is published, the Discord workflow posts the latest stable GitHub release and its updated notes. This includes releases created using `GITHUB_TOKEN`, which would not trigger a separate `release: published` workflow.
- Manual: open **Actions → Notify Discord on Release → Run workflow**. Optionally enter an existing tag (e.g. `v0.7.29`) to post that version. Leave it blank for the latest stable release. Running it manually re-sends the message.
- The notification does **not** run when `Update Release changelog` was triggered only by a code push or when the changelog workflow fails.
- Drafts and pre-releases are excluded.
- If release notes exceed Discord's embed limit, the message shows an excerpt with a link to the full changelog on GitHub.

## Maintaining the workflow

If a new release publisher GitHub Action is created with a different workflow name, add that name to the `workflow_run.workflows` list in `release-changelog.yml` so that a GitHub-token-generated release still runs the changelog updater and therefore notifies Discord.
