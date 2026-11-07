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

- Customer-facing text says MTN Cloud, and commands are shown as `mtncloud`. Networks are MTN Networks and routers MTN Routers.
- The upstream product's name ("Morpheus", "HPE") and the cloud software's names ("OpenStack", "Octavia", ...) appear nowhere in shipped files: not in text, help, comments or tests. The only exceptions are `LICENSE.txt` (the MIT notice must stay) and this file.
- Keep values the appliance or its API defines unchanged even when they contain those names: the `X-Morpheus-Lease` and `X-Morpheus-Token` headers, `MORPHEUS_LEASE_TOKEN`, the `morpheus.yml` fallback, job type codes such as `morpheus.task`, the `morpheus` blueprint and backup provider codes, cloud and option-source codes such as `openstack`. End each such line with `# mtncloud:allow-upstream-name (reason)` or `# mtncloud:allow-cloud-name (reason)`.
- Customers see the platform's own blueprint type as "MTN Cloud" (`-t mtncloud`) and the license registration service as "License Hub".
- `test/naming_test.rb` enforces this on every file and `test/branding_test.rb` on every command's help.

## Releases

Pushing a `v<version>` tag runs `.github/workflows/release.yml`, which publishes to RubyGems. The tag must match `VERSION` in `lib/mtncloud/cli/version.rb`. Push a release tag only when the user asks for one.
