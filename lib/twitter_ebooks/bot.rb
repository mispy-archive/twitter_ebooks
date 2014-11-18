# encoding: utf-8
require 'twitter'
require 'rufus/scheduler'

module Ebooks
  class ConfigurationError < Exception
  end

  # We track how many unprompted interactions the bot has had with
  # each user and start dropping them from mentions after two in a row
  class UserInfo
    attr_reader :username
    attr_accessor :pester_count

    def initialize(username)
      @username = username
      @pester_count = 0
    end

    def can_pester?
      @pester_count < 2
    end
  end

  # Represents a current "interaction state" with another user
  class Interaction
    attr_reader :userinfo, :received, :last_update

    def initialize(userinfo)
      @userinfo = userinfo
      @received = []
      @last_update = Time.now
    end

    def receive(tweet)
      @received << tweet
      @last_update = Time.now
      @userinfo.pester_count = 0
    end

    # Make an informed guess as to whether this user is a bot
    # based on its username and reply speed
    def is_bot?
      if @received.length > 2
        if (@received[-1].created_at - @received[-3].created_at) < 30
          return true
        end
      end

      @userinfo.username.include?("ebooks")
    end

    def continue?
      if is_bot?
        true if @received.length < 2
      else
        true
      end
    end
  end

  class Bot
    attr_accessor :consumer_key, :consumer_secret,
                  :access_token, :access_token_secret

    attr_reader :twitter, :stream, :thread

    # Configuration
    attr_accessor :username, :delay_range, :blacklist

    @@all = [] # List of all defined bots
    def self.all; @@all; end

    def self.get(name)
      all.find { |bot| bot.username == name }
    end

    def log(*args)
      STDOUT.print "@#{@username}: " + args.map(&:to_s).join(' ') + "\n"
      STDOUT.flush
    end

    def initialize(*args, &b)
      @username ||= nil
      @blacklist ||= []
      @delay_range ||= 0

      @users ||= {}
      @interactions ||= {}
      configure(*args, &b)
    end

    def userinfo(username)
      @users[username] ||= UserInfo.new(username)
    end

    def interaction(username)
      if @interactions[username] &&
         Time.now - @interactions[username].last_update < 600
        @interactions[username]
      else
        @interactions[username] = Interaction.new(userinfo(username))
      end
    end

    def make_client
      @twitter = Twitter::REST::Client.new do |config|
        config.consumer_key = @consumer_key
        config.consumer_secret = @consumer_secret
        config.access_token = @access_token
        config.access_token_secret = @access_token_secret
      end

      @stream = Twitter::Streaming::Client.new do |config|
        config.consumer_key = @consumer_key
        config.consumer_secret = @consumer_secret
        config.access_token = @access_token
        config.access_token_secret = @access_token_secret
      end
    end

    # Calculate some meta information about a tweet relevant for replying
    def calc_meta(ev)
      meta = {}
      meta[:mentions] = ev.attrs[:entities][:user_mentions].map { |x| x[:screen_name] }

      # To check if this is someone talking to us, ensure:
      # - The tweet mentions list contains our username
      # - The tweet is not being retweeted by somebody else
      # - Or soft-retweeted by somebody else
      meta[:mentions_bot] = meta[:mentions].map(&:downcase).include?(@username.downcase) && !ev.retweeted_status? && !ev.text.start_with?('RT ')

      # Process mentions to figure out who to reply to
      reply_mentions = meta[:mentions].reject { |m| m.downcase == @username.downcase }
      reply_mentions = reply_mentions.select { |username| userinfo(username).can_pester? }
      meta[:reply_mentions] = [ev.user.screen_name] + reply_mentions

      meta[:reply_prefix] = meta[:reply_mentions].uniq.map { |m| '@'+m }.join(' ') + ' '

      meta[:limit] = 140 - meta[:reply_prefix].length

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
      meta[:mentionless] = mless

      meta
    end

    # Receive an event from the twitter stream
    def receive_event(ev)
      if ev.is_a? Array # Initial array sent on first connection
        log "Online!"
        return
      end

      if ev.is_a? Twitter::DirectMessage
        return if ev.sender.screen_name == @username # Don't reply to self
        log "DM from @#{ev.sender.screen_name}: #{ev.text}"
        fire(:direct_message, ev)

      elsif ev.respond_to?(:name) && ev.name == :follow
        return if ev.source.screen_name == @username
        log "Followed by #{ev.source.screen_name}"
        fire(:follow, ev.source)

      elsif ev.is_a? Twitter::Tweet
        return unless ev.text # If it's not a text-containing tweet, ignore it
        return if ev.user.screen_name == @username # Ignore our own tweets

        meta = calc_meta(ev)

        if meta[:mentions_bot]
          log "Mention from @#{ev.user.screen_name}: #{ev.text}"
          interaction(ev.user.screen_name).receive(ev)
          fire(:mention, ev, meta)
        else
          fire(:timeline, ev, meta)
        end

      elsif ev.is_a? Twitter::Streaming::DeletedTweet
        # pass
      else
        log ev
      end
    end

    def start_stream
      log "starting tweet stream"
      @stream.user do |ev|
        receive_event ev
      end
    end

    def prepare
      # Sanity check
      if @username.nil?
        raise ConfigurationError, "bot.username cannot be nil"
      end

      make_client
      fire(:startup)
    end

    # Connects to tweetstream and opens event handlers for this bot
    def start
      start_stream
    end

    # Fire an event
    def fire(event, *args)
      handler = "on_#{event}".to_sym
      if respond_to? handler
        self.send(handler, *args)
      end
    end

    # Wrapper for EM.add_timer
    # Delays add a greater sense of humanity to bot behaviour
    def delay(&b)
      time = @delay.to_a.sample unless @delay.is_a? Integer
      EM.add_timer(time, &b)
    end

    def blacklisted?(username)
      if @blacklist.include?(username)
        log "Saw scary blacklisted user @#{username}"
        true
      else
        false
      end
    end

    # Reply to a tweet or a DM.
    def reply(ev, text, opts={})
      opts = opts.clone

      if ev.is_a? Twitter::DirectMessage
        return if blacklisted?(ev.sender.screen_name)
        log "Sending DM to @#{ev.sender.screen_name}: #{text}"
        @twitter.create_direct_message(ev.sender.screen_name, text, opts)
      elsif ev.is_a? Twitter::Tweet
        meta = calc_meta(ev)

        if blacklisted?(ev.user.screen_name)
          log "Not replying to blacklisted user @#{ev.user.screen_name}"
          return
        elsif !interaction(ev.user.screen_name).continue?
          log "Not replying to suspected bot @#{ev.user.screen_name}"
          return
        end

        log "Replying to @#{ev.user.screen_name} with: #{meta[:reply_prefix] + text}"
        @twitter.update(meta[:reply_prefix] + text, in_reply_to_status_id: ev.id)

        meta[:reply_mentions].each do |username|
          userinfo(username).pester_count += 1
        end
      else
        raise Exception("Don't know how to reply to a #{ev.class}")
      end
    end

    def favorite(tweet)
      return if blacklisted?(tweet.user.screen_name)
      log "Favoriting @#{tweet.user.screen_name}: #{tweet.text}"

      begin
        @twitter.favorite(tweet.id)
      rescue Twitter::Error::Forbidden
        log "Already favorited: #{tweet.user.screen_name}: #{tweet.text}"
      end
    end

    def retweet(tweet)
      return if blacklisted?(tweet.user.screen_name)
      log "Retweeting @#{tweet.user.screen_name}: #{tweet.text}"

      begin
        @twitter.retweet(tweet.id)
      rescue Twitter::Error::Forbidden
        log "Already retweeted: #{tweet.user.screen_name}: #{tweet.text}"
      end
    end

    def follow(*args)
      log "Following #{args}"

      @twitter.follow(*args)
    end

    def tweet(*args)
      log "Tweeting #{args.inspect}"
      @twitter.update(*args)
    end

    def scheduler
      @scheduler ||= Rufus::Scheduler.new
    end

    # could easily just be *args however the separation keeps it clean.
    def pictweet(txt, pic, *args)
      log "Tweeting #{txt.inspect} - #{pic} #{args}"
      @twitter.update_with_media(txt, File.new(pic), *args)
    end
  end
end
