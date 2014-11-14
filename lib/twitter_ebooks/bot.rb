#!/usr/bin/env ruby
# encoding: utf-8
require 'twitter'
require 'rufus/scheduler'
require 'eventmachine'

module Ebooks
  # Wrap SSLSocket so that readpartial yields the fiber instead of
  # blocking when there is no data
  #
  # We hand this to the twitter library so we can select on the sockets
  # and thus run multiple streams without them blocking
  class FiberSSLSocket
    def initialize(*args)
      @socket = OpenSSL::SSL::SSLSocket.new(*args)
    end

    def readpartial(maxlen)
      data = ""

      loop do
        begin
          data = @socket.read_nonblock(maxlen)
        rescue IO::WaitReadable
        end
        break if data.length > 0
        Fiber.yield(@socket)
      end

      data
    end

    def method_missing(m, *args)
      @socket.send(m, *args)
    end
  end

  # An EventMachine handler which resumes a fiber on incoming data
  class FiberSocketHandler < EventMachine::Connection
    def initialize(fiber)
      @fiber = fiber
    end

    def notify_readable
      @fiber.resume
    end
  end

  class ConfigurationError < Exception
  end

  # UserInfo tracks some meta information for how much
  # we've interacted with a user, and how much they've responded
  class UserInfo
    attr_accessor :times_bugged, :times_responded
    def initialize
      self.times_bugged = 0
      self.times_responded = 0
    end
  end

  class Bot
    attr_accessor :consumer_key, :consumer_secret,
                  :access_token, :access_token_secret

    attr_reader :twitter, :stream

    # Configuration
    attr_accessor :username, :delay_range, :blacklist

    @@all = [] # List of all defined bots
    def self.all; @@all; end

    def self.get(name)
      all.find { |bot| bot.username == name }
    end

    def log(*args)
      STDOUT.puts "@#{@username}: " + args.map(&:to_s).join(' ')
      STDOUT.flush
    end

    def initialize
      @username ||= nil
      @blacklist ||= []
      @delay_range ||= 0

      @users ||= {}
      configure
    end

    def make_client
      @twitter = Twitter::REST::Client.new do |config|
        config.consumer_key = @consumer_key
        config.consumer_secret = @consumer_secret
        config.access_token = @access_token
        config.access_token_secret = @access_token_secret
      end

      @stream = Twitter::Streaming::Client.new(
        ssl_socket_class: FiberSSLSocket
      ) do |config|
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

      reply_mentions = meta[:mentions].reject { |m| m.downcase == @username.downcase }
      reply_mentions = [ev.user.screen_name] + reply_mentions

      # Don't reply to more than three users at a time
      if reply_mentions.length > 3
        log "Truncating reply_mentions to the first three users"
        reply_mentions = reply_mentions[0..2]
      end

      meta[:reply_prefix] = reply_mentions.uniq.map { |m| '@'+m }.join(' ') + ' '

      meta[:limit] = 140 - meta[:reply_prefix].length
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

        # To check if this is a mention, ensure:
        # - The tweet mentions list contains our username
        # - The tweet is not being retweeted by somebody else
        # - Or soft-retweeted by somebody else
        if meta[:mentions].map(&:downcase).include?(@username.downcase) && !ev.retweeted_status? && !ev.text.start_with?('RT ')
          log "Mention from @#{ev.user.screen_name}: #{ev.text}"
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
      log "starting stream for #@username"
      @stream.user do |ev|
        receive_event ev
      end
    end

    # Connects to tweetstream and opens event handlers for this bot
    def start
      # Sanity check
      if @username.nil?
        raise ConfigurationError, "bot.username cannot be nil"
      end

      make_client
      fire(:startup)

      fiber = Fiber.new do
        start_stream
      end

      socket = fiber.resume

      conn = EM.watch socket.io, FiberSocketHandler, fiber
      conn.notify_readable = true
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

        return if blacklisted?(ev.user.screen_name)
        log "Replying to @#{ev.user.screen_name} with: #{text}"
        @twitter.update(meta[:reply_prefix] + text, in_reply_to_status_id: ev.id)
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
