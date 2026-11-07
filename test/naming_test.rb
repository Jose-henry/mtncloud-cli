require 'test/unit'

# The upstream product's name and the cloud software's names must not appear in the CLI: not in
# text customers read, help, comments or tests. Values that the appliance or its API defines keep
# their names, and the line that holds one ends with a marker and the reason:
#
#   'morpheus.task' # mtncloud:allow-upstream-name (API job type code)
#   'openstack'     # mtncloud:allow-cloud-name (API cloud type code)
#
# Checked: every file git tracks, plus new files it doesn't ignore. test/branding_test.rb checks
# the help text the commands print.
#
#   bundle exec ruby -Ilib -Itest test/naming_test.rb
class NamingTest < Test::Unit::TestCase

  ROOT = File.expand_path('..', __dir__)

  # The MIT notice must keep the original copyright, CLAUDE.md is internal notes for coding
  # agents, and this file holds the names it looks for.
  EXEMPT = ['LICENSE.txt', 'CLAUDE.md', 'test/naming_test.rb']

  # The upstream product, its common misspellings and its vendor.
  UPSTREAM = /morpheus|morhpeus|morpehus|morpheous|moprheus|mopheus|morphues|morphus|\bhpe\b/i
  # The cloud software and its parts.
  CLOUD = /openstack|octavia|neutron|keystone|barbican|amphora/i

  UPSTREAM_MARKER = /mtncloud:allow-upstream-name \(\S[^)]*\)/
  CLOUD_MARKER = /mtncloud:allow-cloud-name \(\S[^)]*\)/

  # Lines naming the upstream product or the cloud software without the marker and reason that
  # allow it, as [line number, text].
  def self.violations(text)
    found = []
    text.each_line.with_index(1) do |line, number|
      bad = (line =~ UPSTREAM && line !~ UPSTREAM_MARKER) || (line =~ CLOUD && line !~ CLOUD_MARKER)
      found << [number, line.strip] if bad
    end
    found
  end

  def checked_files
    out = IO.popen(['git', '-C', ROOT, 'ls-files', '-z', '--cached', '--others', '--exclude-standard'], &:read)
    omit("not a git checkout, nothing to check") unless $?.success?
    out.split("\0").reject {|f| EXEMPT.include?(f) || !File.file?(File.join(ROOT, f)) }
  rescue Errno::ENOENT
    omit("git is not installed")
  end

  def test_no_upstream_or_cloud_names_in_the_repository
    files = checked_files
    assert_operator files.size, :>, 100, "expected to check every file in the repository"
    hits = []
    files.each do |f|
      content = File.binread(File.join(ROOT, f))
      next if content.include?("\0") # binary
      content = content.force_encoding('UTF-8').scrub
      self.class.violations(content).each {|n, line| hits << "  #{f}:#{n}: #{line[0, 160]}" }
    end
    assert_empty hits, "The upstream product or the cloud software is named here. Say MTN Cloud " \
      "(MTN Network, MTN Router), or, for a value the API defines, end the line with " \
      "`# mtncloud:allow-upstream-name (reason)` or `# mtncloud:allow-cloud-name (reason)`:\n" +
      hits.first(50).join("\n") + (hits.size > 50 ? "\n  ... and #{hits.size - 50} more" : "")
  end

  def test_names_are_found_in_any_case_and_misspelling
    ["Morpheus Hub", "MORPHEUS_HOME", "the morhpeus cli", "HPE VM Hosts", "OpenStack", "an Octavia listener"].each do |text|
      assert_equal 1, self.class.violations(text).size, "should be found: #{text}"
    end
    ["MTN Cloud", "hyperlink", "a morph target"].each do |text|
      assert_empty self.class.violations(text), "should not be found: #{text}"
    end
  end

  def test_a_marker_with_a_reason_allows_its_own_kind_of_name
    assert_empty self.class.violations("x = 'morpheus.task' # mtncloud:allow-upstream-name (API job type code)")
    assert_empty self.class.violations("x = 'openstack' # mtncloud:allow-cloud-name (API cloud type code)")
    # the marker needs a reason, and only allows its own kind of name
    assert_equal 1, self.class.violations("x = 'morpheus' # mtncloud:allow-upstream-name").size
    assert_equal 1, self.class.violations("x = 'openstack' # mtncloud:allow-upstream-name (wrong marker)").size
  end
end
