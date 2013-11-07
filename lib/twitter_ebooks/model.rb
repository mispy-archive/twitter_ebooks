#!/usr/bin/env ruby
# encoding: utf-8

require 'json'
require 'set'
require 'digest/md5'

module Ebooks
  class Model
    attr_accessor :hash, :sentences, :markov, :keywords

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

    def markov_statement(limit=140, markov=nil)
      markov ||= MarkovModel.build(@sentences)
      tweet = ""

      while (tweet = markov.generate) do
        next if tweet.length > limit
        next if NLP.unmatched_enclosers?(tweet)
        break if tweet.length > limit*0.4 || rand > 0.8
      end

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
    # in the corpus and building a smaller markov model from these
    def markov_response(input, limit=140)
      # First try 
      relevant, slightly_relevant = relevant_sentences(input)

      if relevant.length >= 3
        markov = MarkovModel.new.consume(relevant)
        markov_statement(limit, markov)
      elsif slightly_relevant.length > 5
        markov = MarkovModel.new.consume(slightly_relevant)
        markov_statement(limit, markov)
      else
        markov_statement(limit)
      end
    end
  end
end
