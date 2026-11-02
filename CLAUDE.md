# MTN Cloud CLI

Ruby gem `mtncloud-cli`. It installs the `mtncloud` command and its alias `mcs`. Code is under `lib/mtncloud/` in the `MtnCloud::` namespace. See CONTRIBUTING.md and the README.

## Git workflow (required)

- Never commit or push to `main`. It is protected, and direct pushes are rejected.
- For every code or docs change: create a branch from an up-to-date `main` (`feature/`, `fix/`, `docs/` or `chore/` prefix), commit there, push the branch, and open a pull request against `main` with `gh pr create --base main`.
- Merge only after the **CI passed** check succeeds (`gh pr checks <number> --watch`). Never bypass a failing or pending check.
- Never force-push to `main` and never delete it.

## Testing

- Run `bundle exec rake test:offline` before opening a pull request. CI runs the same task on Ruby 3.3, 3.4 and 4.0.
- Tests that `require 'mtncloud_test'` need a live appliance and are not run by CI.

## Naming

- Customer-facing text says MTN Cloud, and commands are shown as `mtncloud`.
- Keep values the appliance or its API defines unchanged, even though they contain "Morpheus": the `X-Morpheus-Lease` and `X-Morpheus-Token` headers, `MORPHEUS_LEASE_TOKEN`, the `morpheus.yml` fallback, job type codes such as `morpheus.task`, the `morpheus` blueprint and backup provider codes, and Morpheus Hub. `test/branding_test.rb` lists the approved ones.

## Releases

Pushing a `v<version>` tag runs `.github/workflows/release.yml`, which publishes to RubyGems. The tag must match `VERSION` in `lib/mtncloud/cli/version.rb`. Push a release tag only when the user asks for one.
