#!/usr/bin/env ruby
# encoding: utf-8

require 'twitter'
require 'json'

CONFIG_PATH = "#{ENV['HOME']}/.ebooksrc"

module Ebooks
  class Archive
    attr_reader :tweets

    def make_client
      if File.exists?(CONFIG_PATH)
        @config = JSON.parse(File.read(CONFIG_PATH), symbolize_names: true)
      else
        @config = {}

        puts "As Twitter no longer allows anonymous API access, you'll need to enter the auth details of any account to use for archiving. These will be stored in #{CONFIG_PATH} if you need to change them later."
        print "Consumer key: "
        @config[:consumer_key] = STDIN.gets.chomp
        print "Consumer secret: "
        @config[:consumer_secret] = STDIN.gets.chomp
        print "Oauth token: "
        @config[:oauth_token] = STDIN.gets.chomp
        print "Oauth secret: "
        @config[:oauth_token_secret] = STDIN.gets.chomp

        File.open(CONFIG_PATH, 'w') do |f|
          f.write(JSON.pretty_generate(@config))
        end
      end

      Twitter.configure do |config|
        config.consumer_key = @config[:consumer_key]
        config.consumer_secret = @config[:consumer_secret]
        config.oauth_token = @config[:oauth_token]
        config.oauth_token_secret = @config[:oauth_token_secret]
      end

      Twitter::Client.new
    end

    def initialize(username, path, client=nil)
      @username = username
      @path = path || "#{username}.json"
      @client = client || make_client

      if File.exists?(@path)
        @tweets = JSON.parse(File.read(@path), symbolize_names: true)
        log "Currently #{@tweets.length} tweets for #{@username}"
      else
        @tweets.nil?
        log "New archive for @#{username} at #{@path}"
      end
    end

    def sync
      retries = 0
      tweets = []
      max_id = nil

      opts = {
        count: 200,
        #include_rts: false,
        trim_user: true
      }

      opts[:since_id] = @tweets[0][:id] unless @tweets.nil?

      loop do
        opts[:max_id] = max_id unless max_id.nil?
        new = @client.user_timeline(@username, opts)
        break if new.length <= 1
        tweets += new
        puts "Received #{tweets.length} new tweets"
        max_id = new.last.id
      end

      if tweets.length == 0
        log "No new tweets"
      else
        @tweets ||= []
        @tweets = tweets.map(&:attrs).each { |tw|
          tw.delete(:entities)
        } + @tweets
        File.open(@path, 'w') do |f|
          f.write(JSON.pretty_generate(@tweets))
        end
      end
    end
  end
end
