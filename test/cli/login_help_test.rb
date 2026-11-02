require 'test/unit'
require 'stringio'
require 'mtncloud'

# Offline tests for how login explains the username format.
# Sub-tenant users log in as {subdomain}\{username} or {accountID}\{username}.
class LoginHelpTest < Test::Unit::TestCase

  def capture_stdout
    saved = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = saved
  end

  # Captured once: the CLI keeps the stdout it first printed to, so a second
  # --help in the same process would print to the first test's StringIO.
  def login_help
    @@login_help ||= capture_stdout do
      error = assert_raise(SystemExit) { MtnCloud::Cli::Login.new.handle(['--help']) }
      assert_equal 0, error.status
    end
  end

  def test_help_documents_both_sub_tenant_username_formats
    output = login_help
    assert_include output, '{subdomain}\\{username}'
    assert_include output, '{accountID}\\{username}'
    assert_include output, 'Example: acme\\neo'
    assert_include output, 'Example: 2\\neo'
    assert_include output, 'Master tenant users enter only their username.'
  end

  def test_username_option_mentions_subdomain_and_account_id
    output = login_help
    assert_include output, '--username USERNAME'
    assert_include output, 'Sub-tenant users prefix it with their subdomain or account ID'
  end

  def test_prompt_hint_names_both_formats
    hint = MtnCloud::Cli::Credentials::USERNAME_FORMAT
    assert_include hint, 'subdomain\\username'
    assert_include hint, 'accountID\\username'
  end
end
