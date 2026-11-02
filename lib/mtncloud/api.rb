require 'mtncloud/cli/version'
require 'mtncloud/cli/errors'
require 'mtncloud/rest_client'
require 'mtncloud/formatters'
#require 'mtncloud/logging'
#require 'term/ansicolor'

# load interfaces
require 'mtncloud/api/api_client.rb'
require 'mtncloud/api/rest_interface.rb'
require 'mtncloud/api/read_interface.rb'
Dir[File.dirname(__FILE__)  + "/api/**/*.rb"].each {|file| require file }
