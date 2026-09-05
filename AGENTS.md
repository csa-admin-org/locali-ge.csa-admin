# Agent Instructions

## Project Context

Small Sinatra app that receives locali-ge.ch WooCommerce webhooks and creates
members on the matching CSA Admin organization. Product and depot mapping lives
in `config/mapping.yml`.

## Development and Validation

- `mise bootstrap` — install Ruby from `mise.toml`, then gems via `bin/setup`
- `mise run test` — or `mise run t` — `bundle exec ruby test/app_test.rb`
- Tests use Minitest, fixtures in `test/fixtures/`, and WebMock. Stub CSA Admin
  API calls. Do not hit the network.
- Keep `bin/setup` executable.

## Layout

- `app.rb` — HMAC, `/webhook`, `/up`, production boot env
- `lib/webhook.rb` — store mapping, `completed` gate, member POST
- `config/mapping.yml` — per-org `store_id`, `api_endpoint`, WooCommerce IDs
- `config/deploy.yml` — Kamal
- `.github/workflows/tests.yml` / `deploy.yml` — mise-action, then tests or
  `bundle exec kamal deploy`

## Webhooks

- Only `POST /webhook` is authenticated. Verify `X-WC-Webhook-Signature` with
  `WEBHOOK_SECRET` (HMAC-SHA256, Base64).
- After a valid signature, always respond `204`. Member-creation failures must
  not change the HTTP status.
- Process only `status == "completed"`. Other statuses are
  `Webhook::IgnoredStatusError` and are logged, not sent to AppSignal.
- Unknown store is `Webhook::UnkownStoreError` (spelling is existing) and is
  logged only.
- Duplicate-email 422: log only. Other `MemberCreationError` and unexpected
  errors: `Appsignal.report_error`.
- Signed HMAC mismatch: `Kernel.warn` to stderr, then `403 Forbidden`. Unsigned
  probes stay quiet.
- Production boot raises if `WEBHOOK_SECRET` or `APPSIGNAL_PUSH_API_KEY` is blank.

## Mapping and tokens

- Organization key in `mapping.yml` (for example `lejardindemax`) becomes
  `LEJARDINDEMAX_API_TOKEN`.
- `api_endpoint` is in `mapping.yml`, not a separate config file.
- When adding an organization, update `mapping.yml`, `config/deploy.yml`
  secrets, and the deploy workflow secret check together.

## Deploy and secrets

- Production deploys from `main` after Tests is green via
  `.github/workflows/deploy.yml` (`ubuntu-24.04-arm`, Kamal on `isle.thibaud.gg`).
- GitHub Environment `production` holds the Kamal secrets. Sync a local
  `.env.production` with `.agents/scripts/sync_production_env_secrets.sh`. That
  env file is gitignored. Leave `KAMAL_SSH_PRIVATE_KEY` as a GitHub secret only.
- Never dump container `printenv` or log secret values.

## Implementation Style

- Keep this a small Sinatra app. Prefer changes in `app.rb` and `lib/webhook.rb`
  over new layers.
- Follow the existing RuboCop config. Do not add Rails or a JS bundler.
