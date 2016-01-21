#!/usr/bin/env ruby
# encoding: utf-8

require 'json'
require 'set'
require 'digest/md5'
require 'csv'

module Ebooks
  class Model
    # @return [Array<String>]
    # An array of unique tokens. This is the main source of actual strings
    # in the model. Manipulation of a token is done using its index
    # in this array, which we call a "tiki"
    attr_accessor :tokens

    # @return [Array<Array<Integer>>]
    # Sentences represented by arrays of tikis
    attr_accessor :sentences

    # @return [Array<Array<Integer>>]
    # Sentences derived from Twitter mentions
    attr_accessor :mentions

    # @return [Array<String>]
    # The top 200 most important keywords, in descending order
    attr_accessor :keywords

    # Generate a new model from a corpus file
    # @param path [String]
    # @return [Ebooks::Model]
    def self.consume(path)
      Model.new.consume(path)
    end

    # Generate a new model from multiple corpus files
    # @param paths [Array<String>]
    # @return [Ebooks::Model]
    def self.consume_all(paths)
      Model.new.consume_all(paths)
    end

    # Load a saved model
    # @param path [String]
    # @return [Ebooks::Model]
    def self.load(path)
      model = Model.new
      model.instance_eval do
        props = Marshal.load(File.open(path, 'rb') { |f| f.read })
        @tokens = props[:tokens]
        @sentences = props[:sentences]
        @mentions = props[:mentions]
        @keywords = props[:keywords]
      end
      model
    end

    # Save model to a file
    # @param path [String]
    def save(path)
      File.open(path, 'wb') do |f|
        f.write(Marshal.dump({
          tokens: @tokens,
          sentences: @sentences,
          mentions: @mentions,
          keywords: @keywords
        }))
      end
      self
    end

    # Append a generated model to existing model file instead of overwriting it
    # @param path [String]
    def append(path)
      existing = File.file?(path)
      if !existing
        log "No existing model found at #{path}"
        return
      else
        #read-in and deserialize existing model
        props = Marshal.load(File.open(path,'rb') { |old| old.read })
        old_tokens = props[:tokens]
        old_sentences = props[:sentences]
        old_mentions = props[:mentions]
        old_keywords = props[:keywords]

        #append existing properties to new ones and overwrite with new model
        File.open(path, 'wb') do |f|
          f.write(Marshal.dump({
            tokens: @tokens.concat(old_tokens),
            sentences: @sentences.concat(old_sentences),
            mentions: @mentions.concat(old_mentions),
            keywords: @keywords.concat(old_keywords)
          }))
        end
      end
      self
    end


    def initialize
      @tokens = []

      # Reverse lookup tiki by token, for faster generation
      @tikis = {}
    end

    # Reverse lookup a token index from a token
    # @param token [String]
    # @return [Integer]
    def tikify(token)
      if @tikis.has_key?(token) then
        return @tikis[token]
      else
        (@tokens.length+1)%1000 == 0 and puts "#{@tokens.length+1} tokens"
        @tokens << token
        return @tikis[token] = @tokens.length-1
      end
    end

    # Convert a body of text into arrays of tikis
    # @param text [String]
    # @return [Array<Array<Integer>>]
    def mass_tikify(text)
      sentences = NLP.sentences(text)

      sentences.map do |s|
        tokens = NLP.tokenize(s).reject do |t|
          # Don't include usernames/urls as tokens
          t.include?('@') || t.include?('http')
        end

        tokens.map { |t| tikify(t) }
      end
    end

    # Consume a corpus into this model
    # @param path [String]
    def consume(path)
      content = File.read(path, :encoding => 'utf-8')

      if path.split('.')[-1] == "json"
        log "Reading json corpus from #{path}"
        lines = JSON.parse(content).map do |tweet|
          tweet['text']
        end
      elsif path.split('.')[-1] == "csv"
        log "Reading CSV corpus from #{path}"
        content = CSV.parse(content)
        header = content.shift
        text_col = header.index('text')
        lines = content.map do |tweet|
          tweet[text_col]
        end
      else
        log "Reading plaintext corpus from #{path} (if this is a json or csv file, please rename the file with an extension and reconsume)"
        lines = content.split("\n")
      end

      consume_lines(lines)
    end

    # Consume a sequence of lines
    # @param lines [Array<String>]
    def consume_lines(lines)
      log "Removing commented lines and sorting mentions"

      statements = []
      mentions = []
      lines.each do |l|
        next if l.start_with?('#') # Remove commented lines
        next if l.include?('RT') || l.include?('MT') # Remove soft retweets

        if l.include?('@')
          mentions << NLP.normalize(l)
        else
          statements << NLP.normalize(l)
        end
      end

      text = statements.join("\n").encode('UTF-8', :invalid => :replace)
      mention_text = mentions.join("\n").encode('UTF-8', :invalid => :replace)

      lines = nil; statements = nil; mentions = nil # Allow garbage collection

      log "Tokenizing #{text.count("\n")} statements and #{mention_text.count("\n")} mentions"

      @sentences = mass_tikify(text)
      @mentions = mass_tikify(mention_text)

      log "Ranking keywords"
      @keywords = NLP.keywords(text).top(200).map(&:to_s)
      log "Top keywords: #{@keywords[0]} #{@keywords[1]} #{@keywords[2]}"

      self
    end

    # Consume multiple corpuses into this model
    # @param paths [Array<String>]
    def consume_all(paths)
      lines = []
      paths.each do |path|
        content = File.read(path, :encoding => 'utf-8')

        if path.split('.')[-1] == "json"
          log "Reading json corpus from #{path}"
          l = JSON.parse(content).map do |tweet|
            tweet['text']
          end
          lines.concat(l)
        elsif path.split('.')[-1] == "csv"
          log "Reading CSV corpus from #{path}"
          content = CSV.parse(content)
          header = content.shift
          text_col = header.index('text')
          l = content.map do |tweet|
            tweet[text_col]
          end
          lines.concat(l)
        else
          log "Reading plaintext corpus from #{path}"
          l = content.split("\n")
          lines.concat(l)
        end
      end
      consume_lines(lines)
    end

    # Correct encoding issues in generated text
    # @param text [String]
    # @return [String]
    def fix(text)
      NLP.htmlentities.decode text
    end

    # Check if an array of tikis comprises a valid tweet
    # @param tikis [Array<Integer>]
    # @param limit Integer how many chars we have left
    def valid_tweet?(tikis, limit)
      tweet = NLP.reconstruct(tikis, @tokens)
      tweet.length <= limit && !NLP.unmatched_enclosers?(tweet)
    end

    # Generate some text
    # @param limit [Integer] available characters
    # @param generator [SuffixGenerator, nil]
    # @param retry_limit [Integer] how many times to retry on invalid tweet
    # @return [String]
    def make_statement(limit=140, generator=nil, retry_limit=10)
      responding = !generator.nil?
      generator ||= SuffixGenerator.build(@sentences)

      retries = 0
      tweet = ""

      while (tikis = generator.generate(3, :bigrams)) do
        #log "Attempting to produce tweet try #{retries+1}/#{retry_limit}"
        break if (tikis.length > 3 || responding) && valid_tweet?(tikis, limit)

        retries += 1
        break if retries >= retry_limit
      end

      if verbatim?(tikis) && tikis.length > 3 # We made a verbatim tweet by accident
        #log "Attempting to produce unigram tweet try #{retries+1}/#{retry_limit}"
        while (tikis = generator.generate(3, :unigrams)) do
          break if valid_tweet?(tikis, limit) && !verbatim?(tikis)

          retries += 1
          break if retries >= retry_limit
        end
      end

      tweet = NLP.reconstruct(tikis, @tokens)

      if retries >= retry_limit
        log "Unable to produce valid non-verbatim tweet; using \"#{tweet}\""
      end

      fix tweet
    end

    # Test if a sentence has been copied verbatim from original
    # @param tikis [Array<Integer>]
    # @return [Boolean]
    def verbatim?(tikis)
      @sentences.include?(tikis) || @mentions.include?(tikis)
    end

    # Finds relevant and slightly relevant tokenized sentences to input
    # comparing non-stopword token overlaps
    # @param sentences [Array<Array<Integer>>]
    # @param input [String]
    # @return [Array<Array<Array<Integer>>, Array<Array<Integer>>>]
    def find_relevant(sentences, input)
      relevant = []
      slightly_relevant = []

      tokenized = NLP.tokenize(input).map(&:downcase)

      sentences.each do |sent|
        tokenized.each do |token|
          if sent.map { |tiki| @tokens[tiki].downcase }.include?(token)
            relevant << sent unless NLP.stopword?(token)
            slightly_relevant << sent
          end
        end
      end

      [relevant, slightly_relevant]
    end

    # Generates a response by looking for related sentences
    # in the corpus and building a smaller generator from these
    # @param input [String]
    # @param limit [Integer] characters available for response
    # @param sentences [Array<Array<Integer>>]
    # @return [String]
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
