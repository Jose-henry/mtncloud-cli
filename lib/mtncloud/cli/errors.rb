module MtnCloud::Cli

  # A standard error to raise in your CliCommand classes.
  class CommandError < StandardError
    
    attr_reader :args, :optparse, :exit_code
      
    def initialize(msg, args=[], optparse=nil, exit_code=nil)
      @args = args
      @optparse = optparse
      @exit_code = exit_code # || 1
      super(msg)
    end

  end

  # An error indicating the command was not recognized, assigned exit code 127
  class CommandNotFoundError < CommandError
    
    def initialize(msg, args=[], optparse=nil, exit_code=nil)
      super(msg, args, optparse, exit_code || 127)
    end

  end

  # An error for wrong number of arguments
  # could use ::OptionParser::MissingArgument, ::OptionParser::NeedlessArgument
  # maybe return an error code other than 1?
  class CommandArgumentsError < CommandError

    def initialize(msg, args=[], optparse=nil, exit_code=nil)
      super(msg, args, optparse, exit_code || 1)
    end

  end

  # An error indicating authorization is required (unable to aquire access token)
  class AuthorizationRequiredError < CommandError

    def initialize(msg, args=[], optparse=nil, exit_code=nil)
      super(msg, args, optparse, exit_code || 1)
    end
  end

  # An error indicating the user declined to accept a confirmation prompt, assigned exit code 9
  class CommandAborted < CommandError

    def initialize(msg, args=[], optparse=nil, exit_code=nil)
      super(msg, args, optparse, exit_code || 9)
    end
  end

  # A load balancer operation that was refused or could not finish, assigned exit code 1.
  # kind says which:
  #   :access         the login may not run load balancer operations
  #   :refused        the load balancer service refused or failed it, in its own words
  #   :no_answer      the operation ended without an answer
  #   :timed_out      the operation did not finish in time
  #   :job_not_found  the operation's job execution could not be read
  #   :unexpected     the answer is not what the protocol promises
  # details keeps what was seen, for diagnosis: HTTP status, job execution id and status, the raw error.
  class LoadBalancerError < CommandError

    attr_reader :kind, :action, :details, :rolled_back, :left_behind, :piece_id

    def initialize(msg, kind:, action: nil, details: {}, rolled_back: false, left_behind: [], piece_id: nil)
      @kind = kind
      @action = action
      @details = details || {}
      @rolled_back = rolled_back
      @left_behind = left_behind || []
      @piece_id = piece_id
      super(msg, [], nil, 1)
    end
  end

end
