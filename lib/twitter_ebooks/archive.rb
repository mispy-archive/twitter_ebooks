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
        print "Access token: "
        @config[:oauth_token] = STDIN.gets.chomp
        print "Access secret: "
        @config[:oauth_token_secret] = STDIN.gets.chomp

        File.open(CONFIG_PATH, 'w') do |f|
          f.write(JSON.pretty_generate(@config))
        end
      end

      Twitter::REST::Client.new do |config|
        config.consumer_key = @config[:consumer_key]
        config.consumer_secret = @config[:consumer_secret]
        config.access_token = @config[:oauth_token]
        config.access_token_secret = @config[:oauth_token_secret]
      end
    end

    def initialize(username, path=nil, client=nil)
      @username = username
      @path = path || "corpus/#{username}.json"

      if File.directory?(@path)
        @path = File.join(@path, "#{username}.json")
      end

      @client = client || make_client

      if (File.exists?(@path) && !File.zero?(@path))
        @filetext = File.read(@path, :encoding => 'utf-8')
        @tweets = JSON.parse(@filetext, symbolize_names: true)
        log "Currently #{@tweets.length} tweets for #{@username}"
      else
        @tweets.nil?
        log "New archive for @#{username} at #{@path}"
      end
    end

    def sync
      # We use this structure to ensure that
      # a) if there's an issue opening the file, we error out before download
      # b) if there's an issue during download we restore the original
      File.open(@path, 'w') do |file|
        begin
          sync_to(file)
        rescue Exception
          file.seek(0)
          file.write(@filetext)
          raise
        end
      end
    end

    def sync_to(file)
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
        begin
          new = @client.user_timeline(@username, opts)
        rescue Twitter::Error::TooManyRequests
          log "Rate limit exceeded. Waiting for 5 mins before retry."
          sleep 60*5
          retry
        end
        break if new.length <= 1
        tweets += new
        log "Received #{tweets.length} new tweets"
        max_id = new.last.id
      end

      if tweets.length == 0
        log "No new tweets"
      else
        @tweets ||= []
        @tweets = tweets.map(&:attrs).each { |tw|
          tw.delete(:entities)
        } + @tweets
      end
      file.write(JSON.pretty_generate(@tweets))
    end
  end
end
