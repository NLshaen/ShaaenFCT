# CurseForge deployment for ShaaenFCT

The [Publish to CurseForge](workflows/publish-curseforge.yml) GitHub Actions workflow publishes the ZIP **from an existing GitHub Release** to CurseForge's **World of Warcraft** project upload API. It does not create a new GitHub Release or change addon code.

## One-time setup

1. Create/approve the **World of Warcraft addon project** at CurseForge, then copy its numeric **Project ID** from the CurseForge project page. The GitHub repository ID is **not** the CurseForge project ID.
2. Generate a CurseForge **upload API token** from https://www.curseforge.com/account/api-tokens. In GitHub open **NLshaen/ShaaenFCT → Settings → Secrets and variables → Actions → Secrets → New repository secret**, and enter:
   - `CURSEFORGE_API_TOKEN` — the API token (never commit or paste its value into source files).
3. Under **Actions → Variables**, add:
   - `CURSEFORGE_PROJECT_ID` — the numeric CurseForge project ID, e.g. `123456` (example only).
   - `CURSEFORGE_GAME_VERSION_IDS` — the numeric CurseForge **WoW Forever** game version ID(s), comma-separated, e.g. `123,456` (examples only; do **not** use these placeholder IDs). Get the real IDs using `GET https://wow.curseforge.com/api/game/versions` with the `X-Api-Token` header, then choose only compatible versions. The `.toc` `## Interface` number is not a CurseForge game-version ID.
   - `CURSEFORGE_RELEASE_TYPE` — optional: `release` (default), `beta`, or `alpha`.

The job skips publication until **both required variables** have been set. When the variables are available, the workflow still requires the API-token secret; without it the job fails with a clear error. The workflow does not backfill earlier releases automatically.

## When publication happens

The workflow listens for `release: published` and for completion of the repository's release-related GitHub Actions. The second trigger is important: GitHub Releases created by a workflow using `GITHUB_TOKEN` generally do **not** generate another `release: published` workflow run. The `workflow_run` path handles the existing automated release pipeline. You can also go to **Actions → Publish to CurseForge → Run workflow**, specify an existing tag such as `v0.7.29`, and run it manually.

For each run:

1. Resolve the published GitHub Release (specified tag, or latest stable release).
2. Select the expected `ShaaenFCT_vX.Y.Z.zip` asset. A single old-style `shaaenFCT_...zip` is also accepted for previous releases.
3. Validate the ZIP and verify `shaaenFCT/shaaenFCT.toc` matches the Git tag.
4. Upload the ZIP using CurseForge's `POST https://wow.curseforge.com/api/projects/{projectId}/upload-file`, with the GitHub Release description as Markdown changelog.
5. After successful upload, attach `CurseForge_vX.Y.Z.json` to the GitHub Release with the CurseForge file ID. The marker prevents normal reruns from uploading the same version twice.

**Important:** If the remote upload succeeds but writing the marker fails, a retry may duplicate the file. Check the CurseForge project's Files page before manually rerunning that failed job.

## Security and compatibility

- Only the existing `NLshaen/ShaaenFCT` repository is allowed.
- No upload runs if the required project/game-version variables are absent; draft and prerelease GitHub Releases are skipped.
- The token is used solely in the `X-Api-Token` header sent to `wow.curseforge.com`.
- The old BigWigsMods packager workflow no longer has `CF_API_KEY` in its environment to avoid publishing the same version twice to CurseForge.
- To confirm acceptance/approval and supported game versions, check the CurseForge project manually; a successful HTTP upload is not a guarantee that the file is immediately visible in the CurseForge client.

Official documentation: https://support.curseforge.com/support/solutions/articles/9000197321-curseforge-upload-api
