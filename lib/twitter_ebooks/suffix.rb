# encoding: utf-8

module Ebooks
  # This generator uses data similar to a Markov model, but
  # instead of making a chain by looking up bigrams it uses the
  # positions to randomly replace token array suffixes in one sentence
  # with matching suffixes in another
  class SuffixGenerator
    # Build a generator from a corpus of tikified sentences
    # "tikis" are token indexes-- a way of representing words
    # and punctuation as their integer position in a big array
    # of such tokens
    # @param sentences [Array<Array<Integer>>]
    # @return [SuffixGenerator]
    def self.build(sentences)
      SuffixGenerator.new(sentences)
    end

    def initialize(sentences)
      @sentences = sentences.reject { |s| s.empty? }
      @unigrams = {}
      @bigrams = {}

      @sentences.each_with_index do |tikis, i|
        if (i % 10000 == 0) then
          log ("Building: sentence #{i} of #{sentences.length}")
        end
        last_tiki = INTERIM
        tikis.each_with_index do |tiki, j|
          @unigrams[last_tiki] ||= []
          @unigrams[last_tiki] << [i, j]

          @bigrams[last_tiki] ||= {}
          @bigrams[last_tiki][tiki] ||= []

          if j == tikis.length-1 # Mark sentence endings
            @unigrams[tiki] ||= []
            @unigrams[tiki] << [i, INTERIM]
            @bigrams[last_tiki][tiki] << [i, INTERIM]
          else
            @bigrams[last_tiki][tiki] << [i, j+1]
          end

          last_tiki = tiki
        end
      end

      self
    end

    # Generate a recombined sequence of tikis
    # @param passes [Integer] number of times to recombine
    # @param n [Symbol] :unigrams or :bigrams (affects how conservative the model is)
    # @return [Array<Integer>]
    def generate(passes=5, n=:unigrams)
      index = rand(@sentences.length)
      tikis = @sentences[index]
      used = [index] # Sentences we've already used
      verbatim = [tikis] # Verbatim sentences to avoid reproducing

      0.upto(passes-1) do
        varsites = {} # Map bigram start site => next tiki alternatives

        tikis.each_with_index do |tiki, i|
          next_tiki = tikis[i+1]
          break if next_tiki.nil?

          alternatives = (n == :unigrams) ? @unigrams[next_tiki] : @bigrams[tiki][next_tiki]
          # Filter out suffixes from previous sentences
          alternatives.reject! { |a| a[1] == INTERIM || used.include?(a[0]) }
          varsites[i] = alternatives unless alternatives.empty?
        end

        variant = nil
        varsites.to_a.shuffle.each do |site|
          start = site[0]

          site[1].shuffle.each do |alt|
            verbatim << @sentences[alt[0]]
            suffix = @sentences[alt[0]][alt[1]..-1]
            potential = tikis[0..start+1] + suffix

            # Ensure we're not just rebuilding some segment of another sentence
            unless verbatim.find { |v| NLP.subseq?(v, potential) || NLP.subseq?(potential, v) }
              used << alt[0]
              variant = potential
              break
            end
          end

          break if variant
        end

        # If we failed to produce a variation from any alternative, there
        # is no use running additional passes-- they'll have the same result.
        break if variant.nil?

        tikis = variant
      end

      tikis
    end
  end
end
