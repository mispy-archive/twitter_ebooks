# encoding: utf-8

module Ebooks
  # This generator uses data identical to the markov model, but
  # instead of making a chain by looking up bigrams it uses the
  # positions to randomly replace suffixes in one sentence with
  # matching suffixes in another
  class SuffixGenerator
    def self.build(sentences)
      SuffixGenerator.new(sentences)
    end

    def initialize(sentences)
      @sentences = sentences.reject { |s| s.length < 2 }
      @unigrams = {}
      @bigrams = {}

      @sentences.each_with_index do |tokens, i|
        last_token = INTERIM
        tokens.each_with_index do |token, j|
          @unigrams[last_token] ||= []
          @unigrams[last_token] << [i, j]

          @bigrams[last_token] ||= {}
          @bigrams[last_token][token] ||= []

          if j == tokens.length-1 # Mark sentence endings
            @unigrams[token] ||= []
            @unigrams[token] << [i, INTERIM]
            @bigrams[last_token][token] << [i, INTERIM]
          else
            @bigrams[last_token][token] << [i, j+1]
          end

          last_token = token
        end
      end

      self
    end

    def generate(passes=5, n=:unigrams)
      index = rand(@sentences.length)
      tokens = @sentences[index]
      used = [index] # Sentences we've already used
      verbatim = [tokens] # Verbatim sentences to avoid reproducing

      0.upto(passes-1) do
        log NLP.reconstruct(tokens) if $debug
        varsites = {} # Map bigram start site => next token alternatives

        tokens.each_with_index do |token, i|
          next_token = tokens[i+1]
          break if next_token.nil?

          alternatives = (n == :unigrams) ? @unigrams[next_token] : @bigrams[token][next_token]
          # Filter out suffixes from previous sentences
          alternatives.reject! { |a| a[1] == INTERIM || used.include?(a[0]) }
          varsites[i] = alternatives unless alternatives.empty?
        end

        variant = nil
        varsites.to_a.shuffle.each do |site|
          start = site[0]

          site[1].shuffle.each do |alt|
            start, alt = site[0], site[1].sample
            verbatim << @sentences[alt[0]]
            suffix = @sentences[alt[0]][alt[1]..-1]
            potential = tokens[0..start+1] + suffix

            # Ensure we're not just rebuilding some segment of another sentence
            unless verbatim.find { |v| NLP.subseq?(v, potential) || NLP.subseq?(potential, v) }
              used << alt[0]
              variant = potential
              break
            end
          end

          break if variant
        end

        tokens = variant if variant
      end

      tokens
    end
  end
end
