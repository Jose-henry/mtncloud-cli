require 'mtncloud/cli/version'
require 'mtncloud/cli/errors'
require 'mtncloud/rest_client'
require 'mtncloud/formatters'
require 'mtncloud/logging'
require 'mtncloud/util'
require 'mtncloud/routes'
require 'term/ansicolor'

Dir[File.dirname(__FILE__)  + "/ext/*.rb"].each {|file| require file }

module MtnCloud
  module Cli
    
    # The default is $MTNCLOUD_CLI_HOME or $HOME/.mtncloud
    unless defined?(@@home_directory)
      @@home_directory = ENV['MTNCLOUD_CLI_HOME'] || File.join(Dir.home, ".mtncloud")
    end
    
    # get the home directory, where mtncloud-cli stores things
    def self.home_directory
      @@home_directory
    end

    # set the home directory
    def self.home_directory=(fn)
      @@home_directory = fn
    end

    # the name the CLI was invoked as, "mtncloud" or its short alias "mcs".
    # Defaults to "mtncloud" when run some other way, eg. under rake or bundle.
    def self.prog_name
      invoked_name = File.basename($0.to_s, ".*")
      ["mtncloud", "mcs"].include?(invoked_name) ? invoked_name : "mtncloud"
    end

    # check if this is a Windows environment.
    def self.windows?
      if defined?(@@is_windows)
        return @@is_windows
      end
      @@is_windows = false
      begin
        require 'rbconfig'
        @@is_windows = (RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/)
      rescue
        # $stderr.puts "unable to determine if this is a Windows machine."
      end
      return @@is_windows
    end

    # load! does the initial loading of all the CLI utilities and commands
    def self.load!()
      
      # api interfaces
      require 'mtncloud/api'
      Dir[File.dirname(__FILE__)  + "/api/**/*.rb"].each { |file| require file }

      # utilites
      # Dir[File.dirname(__FILE__)  + "/cli/*.rb"].each { |file| require file }
      require 'mtncloud/cli/cli_registry.rb'
      require 'mtncloud/cli/expression_parser.rb'
      require 'mtncloud/cli/dot_file.rb'
      require 'mtncloud/cli/errors'
      require 'mtncloud/cli/cli_command.rb'
      require 'mtncloud/cli/option_types.rb'
      require 'mtncloud/cli/credentials.rb'

      # mixins
      Dir[File.dirname(__FILE__)  + "/cli/mixins/**/*.rb"].each {|file| require file }
      
      # commands
      Dir[File.dirname(__FILE__)  + "/cli/commands/**/*.rb"].each {|file| require file }

    end

    # reload! can be used for live reloading changes while developing
    def self.reload!()
      # api interfaces
      Dir[File.dirname(__FILE__)  + "/api/**/*.rb"].each { |file| load file }
      # mixins
      Dir[File.dirname(__FILE__)  + "/cli/mixins/**/*.rb"].each {|file| load file }
      # commands
      Dir[File.dirname(__FILE__)  + "/cli/commands/**/*.rb"].each {|file| load file }
    end

    # hack needed for unit tests right now
    @@testing = false unless defined?(@@testing)

    # hack needed for unit tests right now
    def self.enable_test_mode
      @@testing = true
    end

    # hack needed for unit tests right now
    def self.testing?
      defined?(@@testing) && @@testing == true
    end

    # require all CLI modules now (on require)
    load!
    
  end

end
