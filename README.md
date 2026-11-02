# MTN Cloud CLI

The MTN Cloud CLI is a command line interface for managing MTN Cloud. You can use it to provision and manage instances, hosts and clusters, deploy applications, run tasks and workflows, and automate most of what you can do in the MTN Cloud UI.

It installs two commands that run the same CLI:

- `mtncloud`
- `mcs`, a short alias for `mtncloud`

## Installation

Requirements:

- Ruby. The CLI is tested on Ruby 3.3. On Windows, install Ruby+Devkit from [rubyinstaller.org](https://rubyinstaller.org/downloads/) and select the option to add Ruby to your PATH.

Install the CLI from RubyGems:

```shell
gem install mtncloud-cli --no-document
```

Check the installation:

```shell
mtncloud version
mcs version
```

On Windows, a first install from a clean environment took about 17 minutes in our testing, mostly spent compiling native extensions for dependencies such as `ffi`, `llhttp-ffi` and `bigdecimal`. Your install time may differ.

### Updating

```shell
gem update mtncloud-cli
```

### Installing from source

To install an unreleased version, build the gem from a clone of this repository. The build needs Git, which it uses to list the files to package.

```shell
git clone https://github.com/Jose-henry/mtncloud-cli
cd mtncloud-cli
gem build mtncloud-cli.gemspec -o mtncloud-cli.gem
gem install ./mtncloud-cli.gem
```

### Docker

The Dockerfile builds the CLI from this repository. Build it from the root of a git clone, because the gem build needs the `.git` directory.

```shell
docker build -t mtncloud-cli .
docker run --rm -it -v ~/.mtncloud:/root/.mtncloud mtncloud-cli remote list
```

The volume keeps your remotes and credentials between runs.

## Usage

Add your MTN Cloud remote, then log in:

```shell
mtncloud remote add mtncloud https://console.cloud.mtn.ng
mtncloud login
```

Then run commands, for example:

```shell
mtncloud instances list
mcs instances list
```

Help is available for every command and subcommand with `-h`:

```shell
mtncloud --help
mcs instances list --help
```

`mtncloud shell` starts an interactive shell. `mtncloud man` opens the full manual, which includes the help for every command.

## Configuration

The CLI keeps its configuration in `~/.mtncloud`. Set `MTNCLOUD_CLI_HOME` to use a different directory, for example to keep separate configurations:

```shell
MTNCLOUD_CLI_HOME=~/.mtncloud_test mtncloud remote list
```

Files in the home directory include:

| File | Contents |
|---|---|
| `appliances` | Your remotes, keyed by name |
| `credentials` | Access tokens for each remote |
| `groups` | The active group for each remote |
| `.mtncloud_profile` | Commands run every time the CLI starts |
| `.mtncloudrc` | Commands run when `mtncloud shell` starts |
| `shell_history` | History for `mtncloud shell` |

The `appliances` and `credentials` files are saved with file permissions `0600`. Only one system user should use a home directory.

Other environment variables:

| Variable | Purpose |
|---|---|
| `MTNCLOUD_PS1` | The prompt for `mtncloud shell`. See `mtncloud set-prompt --help`. |
| `MTNCLOUD_CLI_TMPDIR` | Where temporary shells (`mtncloud shell -Z`) are created. The default is the `tmp` directory inside the home directory. |

## Development

Install the dependencies with Bundler 2. The gemspec requires Bundler `~> 2.2`, so if your default Bundler is newer, install 2.7.2 and use it explicitly:

```shell
gem install bundler:2.7.2
bundle _2.7.2_ install
```

Run the CLI from your working copy:

```shell
bundle _2.7.2_ exec ruby bin/mtncloud --help
bundle _2.7.2_ exec ruby bin/mcs --help
```

To reload your code changes without restarting, start a shell and use `reload`:

```shell
bundle _2.7.2_ exec ruby bin/mtncloud shell --debug
```

Code layout:

- API interfaces are in `lib/mtncloud/api/`.
- CLI commands are in `lib/mtncloud/cli/commands/`.

### Testing

Offline tests don't need an appliance. Run each file with `bundle _2.7.2_ exec ruby -Ilib -Itest <file>`. They include:

- `test/branding_test.rb`, which checks every command's help for leftover non-MTN Cloud branding
- the test files under `test/cli/` and `test/api/` that do not `require 'mtncloud_test'`

The other tests run against a live appliance. Create a `test_config.yaml` in the repository root:

```yaml
url: 'https://console.cloud.mtn.ng'
username: (accountID/Subdomain)\testrunner
password: 'SecretPassword123$'
```

Then run all the tests:

```shell
bundle _2.7.2_ exec rake test
```

## Releasing

New versions are published to RubyGems by the [Publish gem](.github/workflows/release.yml) workflow when a version tag is pushed:

1. Update `VERSION` in `lib/mtncloud/cli/version.rb` and push the change to `main`.
2. Tag the release and push the tag:

   ```shell
   git tag v1.0.1
   git push origin v1.0.1
   ```

The workflow fails if the tag does not match `VERSION`. RubyGems does not accept the same version twice.

The workflow uses RubyGems trusted publishing, so no API key is stored in this repository. On RubyGems.org, the trusted publisher for `mtncloud-cli` names this repository, the `release.yml` workflow and the `release` environment. If the repository moves, update the repository owner and name in that trusted publisher.

## License

MIT. See [LICENSE.txt](LICENSE.txt).
