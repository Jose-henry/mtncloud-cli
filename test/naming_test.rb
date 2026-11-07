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

  # A marker counts only inside a Ruby comment (after #), and only in Ruby files: text that
  # customers read in the docs can never be excused.
  MARKERS = {UPSTREAM => /#.*mtncloud:allow-upstream-name \(([^)]*)\)/, CLOUD => /#.*mtncloud:allow-cloud-name \(([^)]*)\)/}
  MARKED_FILES = /\.rb\z|\Abin\//

  # A reason says what the value is: at least 3 words and 12 characters, and not a placeholder.
  PLACEHOLDER = /\A(reason|todo|tbd|n\/?a|none|ok|fixme|xxx|temp|wip|allowed|needed)\b/i
  def self.meaningful?(reason)
    reason = reason.to_s.strip
    reason.split(/\s+/).size >= 3 && reason.length >= 12 && reason !~ PLACEHOLDER
  end

  # A marker allows a name only where it is part of an identifier, as API values are:
  # lowercase or camelCase ('openstack', 'openStack') or joined to more of the value
  # ('X-Morpheus-Lease', 'MORPHEUS_LEASE_TOKEN'). A name standing on its own as a
  # capitalised word ("Morpheus Hub", "OpenStack.") is prose, and no marker allows it.
  IDENTIFIER_CHAR = /[A-Za-z0-9_.\-\/:$]/
  def self.prose_names(line, names)
    found = []
    line.scan(names) do
      start, stop = $~.offset(0)
      word = $~[0]
      left, right = start, stop
      left -= 1 while left > 0 && line[left - 1] =~ IDENTIFIER_CHAR
      right += 1 while right < line.length && line[right] =~ IDENTIFIER_CHAR
      token = line[left...right].gsub(/\A[.:\/\-$]+|[.:\/\-$]+\z/, '')
      found << word if word[0] !~ /[a-z]/ && token.length == word.length
    end
    found
  end

  # Lines naming the upstream product or the cloud software that no marker allows, as
  # [line number, text, why].
  def self.violations(text, markers_allowed = true)
    found = []
    text.each_line.with_index(1) do |line, number|
      MARKERS.each do |names, marker|
        next unless line =~ names
        why = if !markers_allowed
          "names it in a file where no marker is allowed"
        elsif (m = line.match(marker)).nil?
          "has no marker"
        elsif !meaningful?(m[1])
          "has a marker without a meaningful reason"
        elsif (prose = prose_names(line, names)).any?
          "names #{prose.uniq.join(', ')} as a word; a marker only allows an identifier"
        end
        found << [number, line.strip, why] if why
      end
    end
    found.uniq {|n, _, _| n }
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
      self.class.violations(content, f =~ MARKED_FILES).each {|n, line, why| hits << "  #{f}:#{n} #{why}: #{line[0, 140]}" }
    end
    assert_empty hits, "The upstream product or the cloud software is named here. Say MTN Cloud " \
      "(MTN Network, MTN Router), or, for a value the API defines, end the Ruby line with " \
      "`# mtncloud:allow-upstream-name (what the value is)` or `# mtncloud:allow-cloud-name (what the value is)`:\n" +
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
    assert_empty self.class.violations("h = 'X-Morpheus-Lease' # mtncloud:allow-upstream-name (API header name)")
    assert_empty self.class.violations("v = ENV['MORPHEUS_LEASE_TOKEN'] # mtncloud:allow-upstream-name (lease variable the appliance sets)")
    assert_empty self.class.violations("o = {optionsSourceType: 'openStack'} # mtncloud:allow-cloud-name (API option source type)")
    # only allows its own kind of name
    assert_equal 1, self.class.violations("x = 'openstack' # mtncloud:allow-upstream-name (wrong marker kind)").size
  end

  def test_a_marker_needs_a_meaningful_reason
    ["", "()", "( )", "(x)", "(api code)", "(reason)", "(TODO fix this later)", "(n/a for now please)"].each do |reason|
      line = "x = 'morpheus' # mtncloud:allow-upstream-name #{reason}"
      assert_equal 1, self.class.violations(line).size, "should be refused: #{line}"
    end
  end

  def test_a_marker_cannot_excuse_prose
    [
      "puts \"Morpheus Hub registration\" # mtncloud:allow-upstream-name (API service display name)",
      "print_h1 \"OpenStack Clouds\" # mtncloud:allow-cloud-name (API cloud type display name)",
      "label = 'HPE VM Hosts' # mtncloud:allow-upstream-name (license usage label name)",
      "msg = \"Runs on OpenStack.\" # mtncloud:allow-cloud-name (sentence about the cloud)",
    ].each do |line|
      assert_equal 1, self.class.violations(line).size, "should be refused: #{line}"
    end
  end

  def test_a_marker_only_counts_in_a_ruby_comment
    # not in a comment: the marker text is part of a string
    assert_equal 1, self.class.violations("x = \"morpheus mtncloud:allow-upstream-name (API job type code)\"").size
    # not in a Ruby file: docs customers read are never excused
    assert_equal 1, self.class.violations("Set `morpheus` # mtncloud:allow-upstream-name (API job type code)", false).size
    assert_match MARKED_FILES, "lib/mtncloud/cli.rb"
    assert_match MARKED_FILES, "bin/mtncloud"
    assert_no_match MARKED_FILES, "README.md"
    assert_no_match MARKED_FILES, ".github/pull_request_template.md"
  end
end
