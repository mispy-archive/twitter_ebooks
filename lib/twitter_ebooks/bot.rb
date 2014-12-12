# encoding: utf-8
require 'twitter'
require 'rufus/scheduler'
require 'ostruct'

module Ebooks
  class ConfigurationError < Exception
  end

  # Represents a single reply tree of tweets
  class Conversation
    attr_reader :last_update

    # @param bot [Ebooks::Bot]
    def initialize(bot)
      @bot = bot
      @tweets = []
      @last_update = Time.now
    end

    # @param tweet [Twitter::Tweet] tweet to add
    def add(tweet)
      @tweets << tweet
      @last_update = Time.now
    end

    # Make an informed guess as to whether a user is a bot based
    # on their behavior in this conversation
    def is_bot?(username)
      usertweets = @tweets.select { |t| t.user.screen_name.downcase == username.downcase }

      if usertweets.length > 2
        if (usertweets[-1].created_at - usertweets[-3].created_at) < 10
          return true
        end
      end

      username.include?("ebooks")
    end

    # Figure out whether to keep this user in the reply prefix
    # We want to avoid spamming non-participating users
    def can_include?(username)
      @tweets.length <= 4 ||
        !@tweets[-4..-1].select { |t| t.user.screen_name.downcase == username.downcase }.empty?
    end
  end

  # Meta information about a tweet that we calculate for ourselves
  class TweetMeta
    # @return [Array<String>] usernames mentioned in tweet
    attr_accessor :mentions
    # @return [String] text of tweets with mentions removed
    attr_accessor :mentionless
    # @return [Array<String>] usernames to include in a reply
    attr_accessor :reply_mentions
    # @return [String] mentions to start reply with
    attr_accessor :reply_prefix
    # @return [Integer] available chars for reply
    attr_accessor :limit

    # @return [Ebooks::Bot] associated bot
    attr_accessor :bot
    # @return [Twitter::Tweet] associated tweet
    attr_accessor :tweet

    # Check whether this tweet mentions our bot
    # @return [Boolean]
    def mentions_bot?
      # To check if this is someone talking to us, ensure:
      # - The tweet mentions list contains our username
      # - The tweet is not being retweeted by somebody else
      # - Or soft-retweeted by somebody else
      @mentions.map(&:downcase).include?(@bot.username.downcase) && !@tweet.retweeted_status? && !@tweet.text.match(/([`'‘’"“”]|RT|via|by|from)\s*@/i)
    end

    # @param bot [Ebooks::Bot]
    # @param ev [Twitter::Tweet]
    def initialize(bot, ev)
      @bot = bot
      @tweet = ev

      @mentions = ev.attrs[:entities][:user_mentions].map { |x| x[:screen_name] }

      # Process mentions to figure out who to reply to
      # i.e. not self and nobody who has seen too many secondary mentions
      reply_mentions = @mentions.reject do |m|
        username = m.downcase
        username == @bot.username || !@bot.conversation(ev).can_include?(username)
      end
      @reply_mentions = ([ev.user.screen_name] + reply_mentions).uniq

      @reply_prefix = @reply_mentions.map { |m| '@'+m }.join(' ') + ' '
      @limit = 140 - @reply_prefix.length

      mless = ev.text
      begin
        ev.attrs[:entities][:user_mentions].reverse.each do |entity|
          last = mless[entity[:indices][1]..-1]||''
          mless = mless[0...entity[:indices][0]] + last.strip
        end
      rescue Exception
        p ev.attrs[:entities][:user_mentions]
        p ev.text
        raise
      end
      @mentionless = mless
    end

    # Get an array of media uris in tweet.
    # @param size [String] A twitter image size to return. Supported sizes are thumb, small, medium (default), large
    # @return [Array<String>] image URIs included in tweet
    def media_uris(size_input = '')
      case size_input
      when 'thumb'
        size = ':thumb'
      when 'small'
        size = ':small'
      when 'medium'
        size = ':medium'
      when 'large'
        size = ':large'
      else
        size = ''
      end

      # Start collecting uris.
      uris = []
      if @tweet.media?
        @tweet.media.each do |each_media|
          uris << each_media.media_url.to_s + size
        end
      end

      # and that's pretty much it!
      uris
    end
  end

  class Bot
    # @return [String] OAuth consumer key for a Twitter app
    attr_accessor :consumer_key
    # @return [String] OAuth consumer secret for a Twitter app
    attr_accessor :consumer_secret
    # @return [String] OAuth access token from `ebooks auth`
    attr_accessor :access_token
    # @return [String] OAuth access secret from `ebooks auth`
    attr_accessor :access_token_secret
    # @return [String] Twitter username of bot
    attr_accessor :username
    # @return [Array<String>] list of usernames to block on contact
    attr_accessor :blacklist
    # @return [Hash{String => Ebooks::Conversation}] maps tweet ids to their conversation contexts
    attr_accessor :conversations
    # @return [Range, Integer] range of seconds to delay in delay method
    attr_accessor :delay_range

    # @return [Hash] configuration loaded from config file. may be empty, if no file was loaded
    attr_reader :config

    # @return [Array] list of all defined bots
    def self.all; @@all ||= []; end

    # Fetches a bot by username
    # @param username [String]
    # @return [Ebooks::Bot]
    def self.get(username)
      all.find { |bot| bot.username == username }
    end

    # Logs info to stdout in the context of this bot
    def log(*args)
      STDOUT.print "@#{@username}: " + args.map(&:to_s).join(' ') + "\n"
      STDOUT.flush
    end

    # Initializes and configures bot
    # @param args Arguments passed to configure method
    # @param b Block to call with new bot
    def initialize(username, &b)
      @blacklist ||= []
      @conversations ||= {}
      # Tweet ids we've already observed, to avoid duplication
      @seen_tweets ||= {}

      @username = username
      @delay_range ||= 1..6
      configure

      @config = read_config_file(username)
      @config ||= {}
      freeze_recursive(@config)

      b.call(self) unless b.nil?
      Bot.all << self
    end

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

    # Reads a configuration file for this bot. Completely okay with this not being a configuration file, because then it just does nothing.
    # @param file_name [String] a filename of a config file. doesn't have to be a file, because it could also be a username
    # @return [Hash] data obtained from read_config_file
    def read_config_file(file_name)
      raise 'read_config_file has already been called' if defined? @config
      return unless file_name.match /\.\w+$/
      reader = File.method :read
      case $&.downcase
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
          if virtual_filename.match /.*#{Regexp.escape(File::SEPARATOR)}(.+)\.env$/
            suffix = '_' + $+.upcase
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

      parsed_data
    rescue => exception
      # We don't really care if this fails, because if it did, there probably wasn't a file to read in the first place.
      # Unless we failed if this method was already called, of course.
      raise exception if defined? @config
    end

    def configure
      raise ConfigurationError, "Please override the 'configure' method for subclasses of Ebooks::Bot."
    end

    # Find or create the conversation context for this tweet
    # @param tweet [Twitter::Tweet]
    # @return [Ebooks::Conversation]
    def conversation(tweet)
      conv = if tweet.in_reply_to_status_id?
        @conversations[tweet.in_reply_to_status_id]
      end

      if conv.nil?
        conv = @conversations[tweet.id] || Conversation.new(self)
      end

      if tweet.in_reply_to_status_id?
        @conversations[tweet.in_reply_to_status_id] = conv
      end
      @conversations[tweet.id] = conv

      # Expire any old conversations to prevent memory growth
      @conversations.each do |k,v|
        if v != conv && Time.now - v.last_update > 3600
          @conversations.delete(k)
        end
      end

      conv
    end

    # @return [Twitter::REST::Client] underlying REST client from twitter gem
    def twitter
      @twitter ||= Twitter::REST::Client.new do |config|
        config.consumer_key = @consumer_key
        config.consumer_secret = @consumer_secret
        config.access_token = @access_token
        config.access_token_secret = @access_token_secret
      end
    end

    # @return [Twitter::Streaming::Client] underlying streaming client from twitter gem
    def stream
      @stream ||= Twitter::Streaming::Client.new do |config|
        config.consumer_key = @consumer_key
        config.consumer_secret = @consumer_secret
        config.access_token = @access_token
        config.access_token_secret = @access_token_secret
      end
    end

    # Calculate some meta information about a tweet relevant for replying
    # @param ev [Twitter::Tweet]
    # @return [Ebooks::TweetMeta]
    def meta(ev)
      TweetMeta.new(self, ev)
    end

    # Receive an event from the twitter stream
    # @param ev [Object] Twitter streaming event
    def receive_event(ev)
      if ev.is_a? Array # Initial array sent on first connection
        log "Online!"
        return
      end

      if ev.is_a? Twitter::DirectMessage
        return if ev.sender.screen_name.downcase == @username.downcase # Don't reply to self
        log "DM from @#{ev.sender.screen_name}: #{ev.text}"
        fire(:message, ev)

      elsif ev.respond_to?(:name) && ev.name == :follow
        return if ev.source.screen_name.downcase == @username.downcase
        log "Followed by #{ev.source.screen_name}"
        fire(:follow, ev.source)

      elsif ev.is_a? Twitter::Tweet
        return unless ev.text # If it's not a text-containing tweet, ignore it
        return if ev.user.screen_name.downcase == @username.downcase # Ignore our own tweets

        meta = meta(ev)

        if blacklisted?(ev.user.screen_name)
          log "Blocking blacklisted user @#{ev.user.screen_name}"
          @twitter.block(ev.user.screen_name)
        end

        # Avoid responding to duplicate tweets
        if @seen_tweets[ev.id]
          log "Not firing event for duplicate tweet #{ev.id}"
          return
        else
          @seen_tweets[ev.id] = true
        end

        if meta.mentions_bot?
          log "Mention from @#{ev.user.screen_name}: #{ev.text}"
          conversation(ev).add(ev)
          fire(:mention, ev)
        else
          fire(:timeline, ev)
        end

      elsif ev.is_a?(Twitter::Streaming::DeletedTweet) ||
            ev.is_a?(Twitter::Streaming::Event)
        # pass
      else
        log ev
      end
    end

    # Configures client and fires startup event
    def prepare
      # Sanity check
      if @username.nil?
        raise ConfigurationError, "bot username cannot be nil"
      end

      if @consumer_key.nil? || @consumer_key.empty? ||
         @consumer_secret.nil? || @consumer_key.empty?
        log "Missing consumer_key or consumer_secret. These details can be acquired by registering a Twitter app at https://apps.twitter.com/"
        exit 1
      end

      if @access_token.nil? || @access_token.empty? ||
         @access_token_secret.nil? || @access_token_secret.empty?
        log "Missing access_token or access_token_secret. Please run `ebooks auth`."
        exit 1
      end

      real_name = twitter.user.screen_name

      if real_name != @username
        log "connected to @#{real_name}-- please update config to match Twitter account name"
        @username = real_name
      end

      fire(:startup)
    end

    # Start running user event stream
    def start
      log "starting tweet stream"

      stream.user do |ev|
        receive_event ev
      end
    end

    # Fire an event
    # @param event [Symbol] event to fire
    # @param args arguments for event handler
    def fire(event, *args)
      handler = "on_#{event}".to_sym
      if respond_to? handler
        self.send(handler, *args)
      end
    end

    # Delay an action for a variable period of time
    # @param range [Range, Integer] range of seconds to choose for delay
    def delay(range=@delay_range, &b)
      time = range.to_a.sample unless range.is_a? Integer
      sleep time
      b.call
    end

    # Check if a username is blacklisted
    # @param username [String]
    # @return [Boolean]
    def blacklisted?(username)
      if @blacklist.map(&:downcase).include?(username.downcase)
        true
      else
        false
      end
    end

    # Reply to a tweet or a DM.
    # @param ev [Twitter::Tweet, Twitter::DirectMessage]
    # @param text [String] contents of reply excluding reply_prefix
    # @param opts [Hash] additional params to pass to twitter gem
    def reply(ev, text, opts={})
      opts = opts.clone

      if ev.is_a? Twitter::DirectMessage
        log "Sending DM to @#{ev.sender.screen_name}: #{text}"
        twitter.create_direct_message(ev.sender.screen_name, text, opts)
      elsif ev.is_a? Twitter::Tweet
        meta = meta(ev)

        if conversation(ev).is_bot?(ev.user.screen_name)
          log "Not replying to suspected bot @#{ev.user.screen_name}"
          return false
        end

        log "Replying to @#{ev.user.screen_name} with: #{meta.reply_prefix + text}"
        text = meta.reply_prefix + text unless text.match /@#{Regexp.escape ev.user.screen_name}/i
        tweet = twitter.update(text, opts.merge(in_reply_to_status_id: ev.id))
        conversation(tweet).add(tweet)
        tweet
      else
        raise Exception("Don't know how to reply to a #{ev.class}")
      end
    end

    # Favorite a tweet
    # @param tweet [Twitter::Tweet]
    def favorite(tweet)
      log "Favoriting @#{tweet.user.screen_name}: #{tweet.text}"

      begin
        twitter.favorite(tweet.id)
      rescue Twitter::Error::Forbidden
        log "Already favorited: #{tweet.user.screen_name}: #{tweet.text}"
      end
    end

    # Retweet a tweet
    # @param tweet [Twitter::Tweet]
    def retweet(tweet)
      log "Retweeting @#{tweet.user.screen_name}: #{tweet.text}"

      begin
        twitter.retweet(tweet.id)
      rescue Twitter::Error::Forbidden
        log "Already retweeted: #{tweet.user.screen_name}: #{tweet.text}"
      end
    end

    # Follow a user
    # @param user [String] username or user id
    def follow(user, *args)
      log "Following #{user}"
      twitter.follow(user, *args)
    end

    # Unfollow a user
    # @param user [String] username or user id
    def unfollow(user, *args)
      log "Unfollowing #{user}"
      twiter.unfollow(user, *args)
    end

    # Tweet something
    # @param text [String]
    def tweet(text, *args)
      log "Tweeting '#{text}'"
      twitter.update(text, *args)
    end

    # Get a scheduler for this bot
    # @return [Rufus::Scheduler]
    def scheduler
      @scheduler ||= Rufus::Scheduler.new
    end

    # Tweet some text with an image
    # @param txt [String]
    # @param pic [String] filename
    def pictweet(txt, pic, *args)
      log "Tweeting #{txt.inspect} - #{pic} #{args}"
      twitter.update_with_media(txt, File.new(pic), *args)
    end
  end
end
