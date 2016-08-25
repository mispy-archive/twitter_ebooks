module Ebooks
  class Bot
    # @overload config()
    #   Returns contents of config file that was read when creating bot.
    #   @return [Hash] data obtained from config file.
    # @overload config(file_name)
    #   Reads a configuration file for this bot. Completely okay with this not being a configuration file, because then it just does nothing.
    #   @param file_name [String] a filename of a config file. doesn't have to be a file, because it could also be a username
    #   @return [Hash] data obtained from config file.
    def config(file_name = '')
      # If we have one already, just return it.
      return @config if defined? @config

      # Set @config here so this can't be run again.
      @config = {}

      match_data = file_name.match(/\.\w+$/)
      return unless match_data
      reader = File.method :read
      case match_data.to_s.downcase
      when '.yaml'
        require 'yaml'
        parser = YAML.method :load
      when '.json'
        require 'json'
        parser = JSON.method :parse
      when '.env'
        # Please put these things into your ENV:
        # EBOOKS_USERNAME_SUFFIX, EBOOKS_CONSUMER_KEY_SUFFIX, EBOOKS_CONSUMER_SECRET_SUFFIX
        # EBOOKS_ACCESS_TOKEN_SUFFIX, EBOOKS_ACCESS_TOKEN_SECRET_SUFFIX
        # Where suffix is the word you passed to #new in all caps. ('suffix.env' would be _SUFFIX's filename.)
        def reader_method(virtual_filename)
          # Until we add the 'dotenv' rubygem, this does NOT work with files!
          # if File.file? virtual_filename
            # require 'dotenv'
            # Dotenv.load virtual_filename
          # end

          # First, chop off .env
          prefix = 'EBOOKS_'
          if match_data = virtual_filename.match(/.*#{Regexp.escape(File::SEPARATOR)}(.+)\.env$/)
            suffix = '_' + match_data[-1].upcase
          else
            suffix = '_' + virtual_filename[0...-4].upcase
          end
          return_hash = {}
          ENV.each do |key, value|
            if key.start_with?(prefix) && key.end_with?(suffix)
              return_hash[key] = value
            end
          end
          return [prefix, return_hash, suffix]
        end
        # Grab variables out of hash
        def parser_method(input)
          prefix = input[0]
          parse_hash = input[1]
          suffix = input[2]
          config_hash = {'twitter' => {}}
          config_twitter = config_hash['twitter']

          ['username', 'consumer key', 'consumer secret', 'access token', 'access token secret'].each do |name|
            env_name = prefix + name.upcase.gsub(/ /, '_') + suffix
            config_twitter[name] = parse_hash[env_name] if parse_hash.has_key? env_name
          end

          config_hash
        end

        reader = self.method :reader_method
        parser = self.method :parser_method
      else
        return
      end

      # This line is super fancy.
      parsed_data = parser.call reader.call(file_name)

      # Parse parsed_data a bit.
      if parsed_data.has_key? 'twitter'
        t_config = parsed_data['twitter']

        # Grab username from config
        if t_config.has_key? 'username'
          username = t_config['username']
          username = username[1..-1] if username.start_with? '@'
          @username = username
        end

        # Grab consumer key and secret from config
        @consumer_key = t_config['consumer key'] if t_config.has_key? 'consumer key'
        @consumer_secret = t_config['consumer secret'] if t_config.has_key? 'consumer secret'

        # Grab access token and secret from config
        @access_token = t_config['access token'] if t_config.has_key? 'access token'
        @access_token_secret = t_config['access token secret'] if t_config.has_key? 'access token secret'
      end

      @config = parsed_data

      # Defined here so that method isn't exposed to the rest of bot.rb
      # Used to freeze @config and everything in it, so it can't be edited.
      # @param object to freeze
      def freeze_recursive(object)
        # Does the object contain anything?
        if object.respond_to? :each
          # It might! So recurse through it.
          object.each do |thing|
            # Run this on it as well.
            freeze_recursive(thing)
          end
        end
        # Finally, freeze the object.
        object.freeze
      end

      freeze_recursive @config
    rescue => exception
      # We don't really care if this fails, because if it did, there probably wasn't a file to read in the first place.
    end
  end
end