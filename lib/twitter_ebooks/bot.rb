#!/usr/bin/env ruby
# encoding: utf-8
require 'twitter'
require 'rufus/scheduler'
require 'eventmachine'

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

module Ebooks
  class Bot
    attr_accessor :consumer_key, :consumer_secret,
                  :oauth_token, :oauth_token_secret

    attr_accessor :username

    attr_reader :twitter, :stream

    @@all = [] # List of all defined bots
    def self.all; @@all; end

    def self.get(name)
      all.find { |bot| bot.username == name }
    end

    def initialize(username, &b)
      # Set defaults
      @username = username

      # Override with callback
      b.call(self)

      Bot.all.push(self)
    end

    def log(*args)
      STDOUT.puts "@#{@username}: " + args.map(&:to_s).join(' ')
      STDOUT.flush
    end

    def configure

      @twitter = Twitter::REST::Client.new do |config|
        config.consumer_key = @consumer_key
        config.consumer_secret = @consumer_secret
        config.access_token = @oauth_token
        config.access_token_secret = @oauth_token_secret
      end

      needs_stream = [@on_follow, @on_message, @on_mention, @on_timeline].any? {|e| !e.nil?}

      if needs_stream
        @stream = Twitter::Streaming::Client.new(
          ssl_socket_class: FiberSSLSocket
        ) do |config|
          config.consumer_key = @consumer_key
          config.consumer_secret = @consumer_secret
          config.access_token = @oauth_token
          config.access_token_secret = @oauth_token_secret
        end
      end
    end

    def start_stream
      log "starting stream for #@username"
      @stream.before_request do
        log "Online!"
      end

      @stream.user do |ev|
        p ev

        if ev.is_a? Twitter::DirectMessage
          next if ev.sender.screen_name == @username # Don't reply to self
          log "DM from @#{ev.sender.screen_name}: #{ev.text}"
          @on_message.call(ev) if @on_message
        end

        next unless ev.respond_to? :name

        if ev.name == :follow
          next if ev.source.screen_name == @username
          log "Followed by #{ev.source.screen_name}"
          @on_follow.call(ev.source) if @on_follow
        end

        next unless ev.text # If it's not a text-containing tweet, ignore it
        next if ev.user.screen_name == @username # Ignore our own tweets

        meta = {}
        mentions = ev.attrs[:entities][:user_mentions].map { |x| x[:screen_name] }

        reply_mentions = mentions.reject { |m| m.downcase == @username.downcase }
        reply_mentions = [ev.user.screen_name] + reply_mentions

        meta[:reply_prefix] = reply_mentions.uniq.map { |m| '@'+m }.join(' ') + ' '
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

        # To check if this is a mention, ensure:
        # - The tweet mentions list contains our username
        # - The tweet is not being retweeted by somebody else
        # - Or soft-retweeted by somebody else
        if mentions.map(&:downcase).include?(@username.downcase) && !ev.retweeted_status? && !ev.text.start_with?('RT ')
          log "Mention from @#{ev.user.screen_name}: #{ev.text}"
          @on_mention.call(ev, meta) if @on_mention
        else
          @on_timeline.call(ev, meta) if @on_timeline
        end
      end
    end

    # Connects to tweetstream and opens event handlers for this bot
    def start
      configure

      @on_startup.call if @on_startup

      if not @stream
        log "not bothering with stream for #@username"
        return
      end

      fiber = Fiber.new do
        start_stream
      end

      socket = fiber.resume

      conn = EM.watch socket.io, FiberSocketHandler, fiber
      conn.notify_readable = true
    end

    # Wrapper for EM.add_timer
    # Delays add a greater sense of humanity to bot behaviour
    def delay(time, &b)
      time = time.to_a.sample unless time.is_a? Integer
      EM.add_timer(time, &b)
    end

    # Reply to a tweet or a DM.
    # Applies configurable @reply_delay range
    def reply(ev, text, opts={})
      p "reply???"
      opts = opts.clone

      if ev.is_a? Twitter::DirectMessage
        log "Sending DM to @#{ev.sender.screen_name}: #{text}"
        @twitter.create_direct_message(ev.sender.screen_name, text, opts)
      elsif ev.is_a? Twitter::Tweet
        log "Replying to @#{ev.user.screen_name} with: #{text}"
        @twitter.update(text, in_reply_to_status_id: ev.id)
      else
        raise Exception("Don't know how to reply to a #{ev.class}")
      end
    end

    def scheduler
      @scheduler ||= Rufus::Scheduler.new
    end

    def follow(*args)
      log "Following #{args}"
      @twitter.follow(*args)
    end

    def tweet(*args)
      log "Tweeting #{args.inspect}"
      @twitter.update(*args)
    end

    # could easily just be *args however the separation keeps it clean.
    def pictweet(txt, pic, *args)
      log "Tweeting #{txt.inspect} - #{pic} #{args}"
      @twitter.update_with_media(txt, File.new(pic), *args)
    end

    def on_startup(&b); @on_startup = b; end
    def on_follow(&b); @on_follow = b; end
    def on_mention(&b); @on_mention = b; end
    def on_timeline(&b); @on_timeline = b; end
    def on_message(&b); @on_message = b; end
  end
end
