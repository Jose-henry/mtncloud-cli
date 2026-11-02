# MTN Cloud CLI

The MTN Cloud CLI is a command line interface for managing MTN Cloud. You can use it to provision and manage instances, hosts and clusters, deploy applications, run tasks and workflows, and automate most of what you can do in the MTN Cloud UI.

It installs two commands that run the same CLI:

- `mtncloud`
- `mcs`, a short alias for `mtncloud`

This CLI is derived from HPE's [morpheus-cli](https://github.com/HewlettPackard/morpheus-cli) and is distributed under the MIT license. See [License](#license).

## Installation

The CLI is not published to RubyGems. Build and install it from this repository.

Requirements:

- Ruby. The CLI is tested on Ruby 3.3.
- Git, which the gem build uses to list the files to package.

```shell
git clone https://github.com/Jose-henry/mtncloud-cli
cd mtncloud-cli
gem build mtncloud-cli.gemspec -o mtncloud-cli.gem
gem install ./mtncloud-cli.gem
```

Check the installation:

```shell
mtncloud version
mcs version
```

On Windows, a first install from a clean environment took about 17 minutes in our testing, mostly spent compiling native extensions for dependencies such as `ffi`, `llhttp-ffi` and `bigdecimal`. Your install time may differ.

### Updating

Updates are not installed automatically. To update, run `git pull` in your clone, then run the `gem build` and `gem install` steps above again.

The `mtncloud update` command prints the installed version and these instructions. It does not download or install anything.

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

### Coming from the HPE Morpheus CLI

The MTN Cloud CLI deliberately does not read the Morpheus CLI's configuration. It ignores:

- the `~/.morpheus` directory
- `MORPHEUS_CLI_HOME`
- `MORPHEUS_PS1`
- `MORPHEUS_CLI_TMPDIR`

This means credentials saved for other Morpheus appliances are never used by `mtncloud`. Add your MTN Cloud remote again with `mtncloud remote add`.

Some things are unchanged:

- The `deploy` command reads `mtncloud.yml`, and still reads an existing `morpheus.yml` if there is no `mtncloud.yml`.
- Values that belong to the appliance or its API keep their names, for example the `X-Morpheus-Lease` header and the `MORPHEUS_LEASE_TOKEN` variable that the appliance sets:

  ```shell
  mtncloud whoami -H "X-Morpheus-Lease: $MORPHEUS_LEASE_TOKEN"
  ```

- The `morpheus` command is not installed. Use `mtncloud` or `mcs`.

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

- API interfaces are in `lib/morpheus/api/`.
- CLI commands are in `lib/morpheus/cli/commands/`.

The Ruby namespace is still `Morpheus::`, and the files are still under `lib/morpheus/`. They were kept so that fixes from the upstream HPE project can still be merged.

### Testing

Offline tests don't need an appliance. Run each file with `bundle _2.7.2_ exec ruby -Ilib -Itest <file>`. They include:

- `test/branding_test.rb`, which checks every command's help for leftover Morpheus branding
- the test files under `test/cli/` and `test/api/` that do not `require 'morpheus_test'`

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

## License

MIT. See [LICENSE.txt](LICENSE.txt). This project is derived from HPE's morpheus-cli. The original copyright notice is kept in LICENSE.txt.
