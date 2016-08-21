# encoding: utf-8
require 'twitter'
require 'rufus/scheduler'

# Monkeypatch hack to fix upstream dependency issue
# https://github.com/sferik/twitter/issues/709
class HTTP::URI
  def port
    443 if self.https?
  end
end

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
        if username.include?('ebooks') || (usertweets[-1].created_at - usertweets[-3].created_at) < 12
          return true
        end
      end
    end

    # Figure out whether to keep this user in the reply prefix
    # We want to avoid spamming non-participating users
    def can_include?(username)
      @tweets.length <= 4 ||
        !@tweets.select { |t| t.user.screen_name.downcase == username.downcase }.empty?
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
        m.downcase == @bot.username.downcase || !@bot.conversation(ev).can_include?(m)
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
    # @return [Twitter::User] Twitter user object of bot
    attr_accessor :user
    # @return [String] Twitter username of bot
    attr_accessor :username
    # @return [Array<String>] list of usernames to block on contact
    attr_accessor :blacklist
    # @return [Hash{String => Ebooks::Conversation}] maps tweet ids to their conversation contexts
    attr_accessor :conversations
    # @return [Range, Integer] range of seconds to delay in delay method
    attr_accessor :delay_range

    # @return [Array] list of all defined bots
    def self.all; @@all ||= []; end

    # Fetches a bot by username
    # @param username [String]
    # @return [Ebooks::Bot]
    def self.get(username)
      all.find { |bot| bot.username.downcase == username.downcase }
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

      b.call(self) unless b.nil?
      Bot.all << self
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
      case ev
      when Array # Initial array sent on first connection
        log "Online!"
        fire(:connect, ev)
        return
      when Twitter::DirectMessage
        return if ev.sender.id == @user.id # Don't reply to self
        log "DM from @#{ev.sender.screen_name}: #{ev.text}"
        fire(:message, ev)
      when Twitter::Tweet
        return unless ev.text # If it's not a text-containing tweet, ignore it
        return if ev.user.id == @user.id # Ignore our own tweets

        if ev.retweet? && ev.retweeted_tweet.user.id == @user.id
          # Someone retweeted our tweet!
          fire(:retweet, ev)
          return
        end

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
      when Twitter::Streaming::Event
        case ev.name
        when :follow
          return if ev.source.id == @user.id
          log "Followed by #{ev.source.screen_name}"
          fire(:follow, ev.source)
        when :favorite, :unfavorite
          return if ev.source.id == @user.id # Ignore our own favorites
          log "@#{ev.source.screen_name} #{ev.name.to_s}d: #{ev.target_object.text}"
          fire(ev.name, ev.source, ev.target_object)
        when :user_update
          update_myself ev.source
        end
      when Twitter::Streaming::DeletedTweet
        # Pass
      else
        log ev
      end
    end

    # Updates @user and calls on_user_update.
    def update_myself(new_me=twitter.user)
      @user = new_me if @user.nil? || new_me.id == @user.id
      @username = @user.screen_name
      log 'User information updated'
      fire(:user_update)
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

      # Save old name
      old_name = username
      # Load user object and actual username
      update_myself
      # Warn about mismatches unless it was clearly intentional
      log "warning: bot expected to be @#{old_name} but connected to @#{username}" unless username == old_name || old_name.empty?

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
      time = rand(range) unless range.is_a? Integer
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

        text = meta.reply_prefix + text unless text.match(/@#{Regexp.escape ev.user.screen_name}/i)
        log "Replying to @#{ev.user.screen_name} with: #{text}"
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
      twitter.unfollow(user, *args)
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
