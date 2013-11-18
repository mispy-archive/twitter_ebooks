#!/usr/bin/env ruby
# encoding: utf-8

require 'json'
require 'set'
require 'digest/md5'

module Ebooks
  class Model
    attr_accessor :hash, :sentences, :mentions, :keywords

    def self.consume(txtpath)
      Model.new.consume(txtpath)
    end

    def self.load(path)
      Marshal.load(File.read(path))
    end

    def consume(txtpath)
      # Record hash of source file so we know to update later
      @hash = Digest::MD5.hexdigest(File.read(txtpath))

      text = File.read(txtpath)
      log "Removing commented lines and sorting mentions"

      lines = text.split("\n")
      keeping = []
      mentions = []
      lines.each do |l|
        next if l.start_with?('#') # Remove commented lines
        next if l.include?('RT') || l.include?('MT') # Remove soft retweets
        
        if l.include?('@')
          mentions << l
        else
          keeping << l
        end
      end
      text = NLP.normalize(keeping.join("\n")) # Normalize weird characters
      mention_text = NLP.normalize(mentions.join("\n"))

      log "Segmenting text into sentences"

      statements = NLP.sentences(text)
      mentions = NLP.sentences(mention_text)

      log "Tokenizing #{statements.length} statements and #{mentions.length} mentions"
      @sentences = []
      @mentions = []

      statements.each do |s|
        @sentences << NLP.tokenize(s).reject do |t|
          t.start_with?('@') || t.start_with?('http')
        end
      end

      mentions.each do |s|
        @mentions << NLP.tokenize(s).reject do |t|
          t.start_with?('@') || t.start_with?('http')
        end
      end

      log "Ranking keywords"
      @keywords = NLP.keywords(@sentences)

      self
    end

    def save(path)
      File.open(path, 'w') do |f|
        f.write(Marshal.dump(self))
      end
      self
    end

    def fix(tweet)
      # This seems to require an external api call
      #begin
      #  fixer = NLP.gingerice.parse(tweet)
      #  log fixer if fixer['corrections']
      #  tweet = fixer['result']
      #rescue Exception => e
      #  log e.message
      #  log e.backtrace
      #end

      NLP.htmlentities.decode tweet
    end

    def valid_tweet?(tokens, limit)
      tweet = NLP.reconstruct(tokens)
      tweet.length <= limit && !NLP.unmatched_enclosers?(tweet)
    end

    def make_statement(limit=140, generator=nil, retry_limit=10)
      responding = !generator.nil?
      generator ||= SuffixGenerator.build(@sentences)

      retries = 0
      tweet = ""

      while (tokens = generator.generate(3, :bigrams)) do
        next if tokens.length <= 3 && !responding
        break if valid_tweet?(tokens, limit)

        retries += 1
        break if retries >= retry_limit
      end

      if verbatim?(tokens) && tokens.length > 3 # We made a verbatim tweet by accident
        while (tokens = generator.generate(3, :unigrams)) do
          break if valid_tweet?(tokens, limit) && !verbatim?(tokens)

          retries += 1
          break if retries >= retry_limit
        end
      end

      tweet = NLP.reconstruct(tokens)

      if retries >= retry_limit
        log "Unable to produce valid non-verbatim tweet; using \"#{tweet}\""
      end

      fix tweet
    end

    # Test if a sentence has been copied verbatim from original
    def verbatim?(tokens)
      @sentences.include?(tokens) || @mentions.include?(tokens)
    end

    # Finds all relevant tokenized sentences to given input by
    # comparing non-stopword token overlaps
    def find_relevant(sentences, input)
      relevant = []
      slightly_relevant = []

      tokenized = NLP.tokenize(input).map(&:downcase)

      sentences.each do |sent|
        tokenized.each do |token|
          if sent.map(&:downcase).include?(token)
            relevant << sent unless NLP.stopword?(token)
            slightly_relevant << sent
          end
        end
      end

      [relevant, slightly_relevant]
    end

    # Generates a response by looking for related sentences
    # in the corpus and building a smaller generator from these
    def make_response(input, limit=140, sentences=@mentions)
      # Prefer mentions
      relevant, slightly_relevant = find_relevant(sentences, input)

      if relevant.length >= 3
        generator = SuffixGenerator.build(relevant)
        make_statement(limit, generator)
      elsif slightly_relevant.length >= 5
        generator = SuffixGenerator.build(slightly_relevant)
        make_statement(limit, generator)
      elsif sentences.equal?(@mentions)
        make_response(input, limit, @sentences)
      else
        make_statement(limit)
      end
    end
  end
end
