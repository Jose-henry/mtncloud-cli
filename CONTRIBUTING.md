# Contributing to the MTN Cloud CLI

Thank you for helping improve the MTN Cloud CLI. This guide explains how changes get into the project.

## How changes reach main

`main` is protected. Nobody pushes to it directly, including maintainers. Every change goes through a pull request:

1. Update your local `main`:

   ```shell
   git checkout main
   git pull
   ```

2. Create a branch for your change:

   ```shell
   git checkout -b fix/clusters-get-help
   ```

   Name the branch after the change, with a prefix: `feature/`, `fix/`, `docs/` or `chore/`.

3. Make your change, run the offline tests (see [Testing](#testing)), and commit.
4. Push the branch and open a pull request against `main`:

   ```shell
   git push -u origin fix/clusters-get-help
   gh pr create --base main
   ```

5. Wait for the **CI passed** check. It runs the offline tests on Ruby 3.3, 3.4 and 4.0 and builds the gem.
6. When CI passes, merge the pull request. A pull request cannot be merged while CI is failing or still running.

If CI fails, push more commits to the same branch. CI runs again on every push.

## Setting up

Requirements:

- Ruby 3.3 or newer
- Bundler 2
- Git

```shell
git clone https://github.com/Jose-henry/mtncloud-cli
cd mtncloud-cli
bundle install
```

Run the CLI from your working copy:

```shell
bundle exec ruby bin/mtncloud --help
```

See [Development](README.md#development) in the README for the code layout.

## Testing

Run the offline tests before you open a pull request. They don't need an MTN Cloud appliance, and they are the same tests CI runs:

```shell
bundle exec rake test:offline
```

Add or update tests for the behaviour you change. A test that doesn't need an appliance must not `require 'mtncloud_test'`, so that `test:offline` and CI run it.

`test/branding_test.rb` fails if any command's help mentions Morpheus, except for values that belong to the appliance, such as the `X-Morpheus-Lease` header. Keep it passing.

The tests that need a live appliance are described in [Testing](README.md#testing) in the README. Run them when you change how the CLI talks to the API.

## Writing changes

- Keep each pull request to one change. Separate refactoring from behaviour changes.
- Follow the style of the code around your change.
- Customer-facing text says **MTN Cloud**, and commands are shown as `mtncloud`. Values that the appliance or its API defines keep their names, for example `X-Morpheus-Lease` and `MORPHEUS_LEASE_TOKEN`.
- Update the README when you change how the CLI is installed, configured or used.

## Commit messages

- Write a short summary line in the imperative mood, for example "Fix clusters get usage on Ruby 3.4".
- If the reason for the change isn't obvious, explain it in the body.

## Releases

Maintainers publish releases. See [Releasing](README.md#releasing) in the README. The version bump goes through a pull request like any other change, and the version tag is pushed after that pull request is merged.

## License

By contributing, you agree that your contributions are licensed under the project's [MIT license](LICENSE.txt).
