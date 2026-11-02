require "bundler/gem_tasks"
require "rake/testtask"

# Every test, including the ones that need a live appliance (see README > Testing).
Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList['test/**/*_test.rb']
end

# Tests that need a live appliance load the mtncloud_test helper.
OFFLINE_TESTS = FileList['test/**/*_test.rb'].exclude('test/mtncloud_test.rb').reject do |f|
  File.read(f).include?("require 'mtncloud_test'")
end

desc "Run the tests that do not need a live appliance, one file at a time"
task "test:offline" do
  failed = OFFLINE_TESTS.reject do |f|
    puts "== #{f}"
    ruby("-Ilib", "-Itest", f) { |ok, _status| ok }
  end
  abort "Failed: #{failed.join(', ')}" unless failed.empty?
  puts "All #{OFFLINE_TESTS.size} offline test files passed."
end

#task :default => :test
