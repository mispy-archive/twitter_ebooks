# encoding: utf-8
require 'twitter'
require 'rufus/scheduler'

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
        if (usertweets[-1].created_at - usertweets[-3].created_at) < 30
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
      configure

      b.call(self) unless b.nil?
      Bot.all << self
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
        fire(:direct_message, ev)

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
        tweet = twitter.update(meta.reply_prefix + text, in_reply_to_status_id: ev.id)
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
    # @param pic [String] or [[String]] filename
    # @param opt_update [Hash] options passed to update (optional)
    # @param opt_upload [Hash] options passed to upload (twitter gem supports this, but I'm not even sure what it's for)
    def pictweet(txt, pic, *args)
      # Set opt_update to first *args argument or an empty hash
      opt_update = args[0].is_a?(Hash) ? args[0] : {}
      # Set opt_update to second *args argument or an empty hash
      opt_upload = args[1].is_a?(Hash) ? args[1] : {}

      # If pic isn't an array, make it one.
      pic = [pic] unless pic.is_a? Array
      # Currently, only this many images are allowed per tweet.
      pic = pic[0...4] unless pic.length < 4 # Using three dots in range so both numbers can be the same (less confusion)

      images_to_tweet_for_log = pic.join ' '
      log "Tweeting '#{txt}' and #{pic.length} images: #{images_to_tweet_for_log}"

      # The Twitter website currently has a bug with displaying multiple images if a tweet is marked as possibly_sensitive
      if pic.length > 1 && opt_update[:possibly_sensitive]
        log 'Warning: Tweets with multiple images might not show up properly on all devices if :possibly_sensitive is enabled.'
      end

      # Create an array to store picture IDs
      pic_id = []
      pic.each do |each_pic|
        # Try to find the file.
        each_pic_picture = File.new each_pic.to_s
        # Upload it, and store its ID from Twitter.
        pic_id << twitter.upload(each_pic_picture, opt_upload)
      end

      # Prepare media_ids for uploading.
      opt_update[:media_ids] = pic_id.join ',' # This will replace media_ids if it was passed into this method, but I don't know why anyone would do that.

      twitter.update(txt, opt_update)
    end
  end
end
