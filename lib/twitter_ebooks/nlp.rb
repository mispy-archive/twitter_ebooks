# encoding: utf-8
require 'fast-stemmer'
require 'highscore'

module Ebooks
  module NLP
    # We deliberately limit our punctuation handling to stuff we can do consistently
    # It'll just be a part of another token if we don't split it out, and that's fine
    PUNCTUATION = ".?!,"

    # Lazy-load NLP libraries and resources
    # Some of this stuff is pretty heavy and we don't necessarily need
    # to be using it all of the time

    def self.stopwords
      @stopwords ||= File.read(File.join(DATA_PATH, 'stopwords.txt')).split
    end

    def self.nouns
      @nouns ||= File.read(File.join(DATA_PATH, 'nouns.txt')).split
    end

    def self.adjectives
      @adjectives ||= File.read(File.join(DATA_PATH, 'adjectives.txt')).split
    end

    # POS tagger
    def self.tagger
      require 'engtagger'
      @tagger ||= EngTagger.new
    end

    # Gingerice text correction service
    def self.gingerice
      require 'gingerice'
      Gingerice::Parser.new # No caching for this one
    end

    # For decoding html entities
    def self.htmlentities
      require 'htmlentities'
      @htmlentities ||= HTMLEntities.new
    end

    ### Utility functions
    
    # We don't really want to deal with all this weird unicode punctuation
    def self.normalize(text)
      htmlentities.decode text.gsub('“', '"').gsub('”', '"').gsub('’', "'").gsub('…', '...')
    end

    # Split text into sentences
    # We use ad hoc approach because fancy libraries do not deal
    # especially well with tweet formatting, and we can fake solving
    # the quote problem during generation
    def self.sentences(text)
      text.split(/\n+|(?<=[.?!])\s+/)
    end

    # Split a sentence into word-level tokens
    # As above, this is ad hoc because tokenization libraries
    # do not behave well wrt. things like emoticons and timestamps
    def self.tokenize(sentence)
      regex = /\s+|(?<=[#{PUNCTUATION}]\s)(?=[a-zA-Z])|(?<=[a-zA-Z])(?=[#{PUNCTUATION}]+\s)/
      sentence.split(regex)
    end

    def self.stem(word)
      Stemmer::stem_word(word.downcase)
    end

    def self.keywords(sentences)
      # Preprocess to remove stopwords (highscore's blacklist is v. slow)
      text = sentences.flatten.reject { |t| stopword?(t) }.join(' ')

      text = Highscore::Content.new(text)

      text.configure do
        #set :multiplier, 2
        #set :upper_case, 3
        #set :long_words, 2
        #set :long_words_threshold, 15
        #set :vowels, 1                     # => default: 0 = not considered
        #set :consonants, 5                 # => default: 0 = not considered
        #set :ignore_case, true             # => default: false
        set :word_pattern, /(?<!@)(?<=\s)[\w']+/           # => default: /\w+/
        #set :stemming, true                # => default: false
      end

      text.keywords
    end

    # Takes a list of tokens and builds a nice-looking sentence
    def self.reconstruct(tokens)
      text = ""
      last_token = nil
      tokens.each do |token|
        next if token == INTERIM
        text += ' ' if last_token && space_between?(last_token, token)
        text += token
        last_token = token
      end
      text
    end

    # Determine if we need to insert a space between two tokens
    def self.space_between?(token1, token2)
      p1 = self.punctuation?(token1)
      p2 = self.punctuation?(token2)
      if p1 && p2 # "foo?!"
        false
      elsif !p1 && p2 # "foo."
        false
      elsif p1 && !p2 # "foo. rah"
        true
      else # "foo rah"
        true
      end
    end

    def self.punctuation?(token)
      (token.chars.to_set - PUNCTUATION.chars.to_set).empty?
    end

    def self.stopword?(token)
      @stopword_set ||= stopwords.map(&:downcase).to_set
      @stopword_set.include?(token.downcase)
    end

    # Determine if a sample of text contains unmatched brackets or quotes
    # This is one of the more frequent and noticeable failure modes for
    # the markov generator; we can just tell it to retry
    def self.unmatched_enclosers?(text)
      enclosers = ['**', '""', '()', '[]', '``', "''"]
      enclosers.each do |pair|
        starter = Regexp.new('(\W|^)' + Regexp.escape(pair[0]) + '\S')
        ender = Regexp.new('\S' + Regexp.escape(pair[1]) + '(\W|$)')

        opened = 0

        tokenize(text).each do |token|
          opened += 1 if token.match(starter)
          opened -= 1 if token.match(ender)

          return true if opened < 0 # Too many ends!
        end

        return true if opened != 0 # Mismatch somewhere.
      end

      false
    end

    # Determine if a2 is a subsequence of a1
    def self.subseq?(a1, a2)
      a1.each_index.find do |i|
        a1[i...i+a2.length] == a2
      end
    end
  end
end
