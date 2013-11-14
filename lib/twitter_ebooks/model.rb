#!/usr/bin/env ruby
# encoding: utf-8

require 'json'
require 'set'
require 'digest/md5'

module Ebooks
  class Model
    attr_accessor :hash, :sentences, :generator, :keywords

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
      log "Removing commented lines and mention tokens"

      lines = text.split("\n")
      keeping = []
      lines.each do |l|
        next if l.start_with?('#') || l.include?('RT')
        processed = l.split.reject { |w| w.include?('@') || w.include?('http') }
        keeping << processed.join(' ')
      end
      text = NLP.normalize(keeping.join("\n"))

      log "Segmenting text into sentences"

      sentences = NLP.sentences(text)

      log "Tokenizing #{sentences.length} sentences"
      @sentences = sentences.map { |sent| NLP.tokenize(sent) }

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

    def make_statement(limit=140, generator=nil)
      responding = !generator.nil?
      generator ||= SuffixGenerator.build(@sentences)
      tweet = ""

      while (tokens = generator.generate(3, :bigrams)) do
        next if tokens.length <= 3 && !responding
        break if valid_tweet?(tokens, limit)
      end

      if @sentences.include?(tokens) && tokens.length > 3 # We made a verbatim tweet by accident
        while (tokens = generator.generate(3, :unigrams)) do
          break if valid_tweet?(tokens, limit) && !@sentences.include?(tokens)
        end
      end

      tweet = NLP.reconstruct(tokens)

      fix tweet
    end

    # Finds all relevant tokenized sentences to given input by
    # comparing non-stopword token overlaps
    def relevant_sentences(input)
      relevant = []
      slightly_relevant = []

      tokenized = NLP.tokenize(input)

      @sentences.each do |sent|
        tokenized.each do |token|
          if sent.include?(token)
            relevant << sent unless NLP.stopword?(token)
            slightly_relevant << sent
          end
        end
      end

      [relevant, slightly_relevant]
    end

    # Generates a response by looking for related sentences
    # in the corpus and building a smaller generator from these
    def make_response(input, limit=140)
      # First try 
      relevant, slightly_relevant = relevant_sentences(input)

      if relevant.length >= 3
        generator = SuffixGenerator.build(relevant)
        make_statement(limit, generator)
      elsif slightly_relevant.length >= 5
        generator = SuffixGenerator.build(slightly_relevant)
        make_statement(limit, generator)
      else
        make_statement(limit)
      end
    end
  end
end
