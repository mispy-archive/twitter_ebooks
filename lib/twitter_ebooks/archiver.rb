#!/usr/bin/env ruby
# encoding: utf-8

require 'twitter'

module Ebooks
  class Archiver
    def initialize(username, outpath)
      @username = username
      @outpath = outpath
      @client = Twitter::Client.new
    end

    # Read exiting corpus into memory.
    # Return list of tweet lines and the last tweet id.
    def read_corpus
      lines = []
      since_id = nil

      if File.exists?(@outpath)
        lines = File.read(@outpath).split("\n")
        if lines[0].start_with?('#')
          since_id = lines[0].split('# ').last
        end
      end

      [lines, since_id]
    end

    # Retrieve all available tweets for a given user since the last tweet id
    def tweets_since(since_id)
      page = 1
      retries = 0
      tweets = []
      max_id = nil

      opts = {
        count: 200,
        include_rts: false,
        trim_user: true
      }

      opts[:since_id] = since_id unless since_id.nil?

      loop do
        opts[:max_id] = max_id unless max_id.nil?
        new = @client.user_timeline(@username, opts)
        break if new.length <= 1
        puts "Received #{new.length} tweets"
        tweets += new
        max_id = new.last.id
        break
      end

      tweets
    end

    def fetch_tweets
      lines, since_id = read_corpus

      if since_id.nil?
        puts "Retrieving tweets from @#{@username}"
      else
        puts "Retrieving tweets from @#{@username} since #{since_id}"
      end

      tweets = tweets_since(since_id)

      if tweets.length == 0
        puts "No new tweets"
        return
      end

      new_lines = tweets.map { |tweet| tweet.text.gsub("\n", " ") }
      new_since_id = tweets[0].id.to_s
      lines = ["# " + new_since_id] + new_lines + lines
      corpus = File.open(@outpath, 'w')
      corpus.write(lines.join("\n"))
      corpus.close
    end
  end
end
