# Playtest Portal (Netlify)

This project includes a one-page static portal at `playtest-site/` and automatic deploy via GitHub Actions.

## What Was Added
- Portal HTML: `playtest-site/index.html`
- Download link config: `playtest-site/portal-config.js`
- Password gate (Edge Function): `netlify/edge-functions/basic-auth.ts`
- Netlify config: `netlify.toml`
- Deploy workflow: `.github/workflows/deploy-playtest-portal.yml`

## Netlify Setup
1. Create/import the site in Netlify from this repo.
2. In Netlify site settings, set Environment Variables:
   - `PLAYTEST_USER` = your portal username
   - `PLAYTEST_PASS` = your portal password
   - `PLAYTEST_LINUX_URL` = Linux download URL
   - `PLAYTEST_WINDOWS_URL` = Windows download URL
   - `PLAYTEST_BUILD_STAMP` = build label shown on page (example: `2026-02-21 build-07`)
3. Ensure build publish directory is `playtest-site` (already in `netlify.toml`).

## GitHub Secrets
Set these in GitHub repo -> Settings -> Secrets and variables -> Actions:
- `NETLIFY_AUTH_TOKEN`
- `NETLIFY_SITE_ID`

## Updating Download Links
Preferred: update Netlify environment variables:
- `PLAYTEST_LINUX_URL`
- `PLAYTEST_WINDOWS_URL`
- `PLAYTEST_BUILD_STAMP`

Optional local fallback for preview/dev:
- `playtest-site/portal-config.js` (`window.PLAYTEST_PORTAL`)

## Deploy Trigger
The workflow deploys automatically on push to `main` when portal/netlify files change, or manually via `workflow_dispatch`.

## Security Notes
- The portal is protected with HTTP Basic Auth via Netlify Edge Function.
- Do not commit real credentials; credentials come from Netlify env vars only.
