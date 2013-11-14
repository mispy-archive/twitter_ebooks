module Ebooks
  # Special INTERIM token represents sentence boundaries
  # This is so we can include start and end of statements in model
  # Due to the way the sentence tokenizer works, can correspond
  # to multiple actual parts of text (such as ^, $, \n and .?!)
  INTERIM = :interim

  # This is an ngram-based Markov model optimized to build from a
  # tokenized sentence list without requiring too much transformation
  class MarkovModel
    def self.build(sentences)
      MarkovModel.new.consume(sentences)
    end

    def consume(sentences)
      # These models are of the form ngram => [[sentence_pos, token_pos] || INTERIM, ...]
      # We map by both bigrams and unigrams so we can fall back to the latter in
      # cases where an input bigram is unavailable, such as starting a sentence
      @sentences = sentences
      @unigrams = {}
      @bigrams = {}

      sentences.each_with_index do |tokens, i|
        last_token = INTERIM
        tokens.each_with_index do |token, j|
          @unigrams[last_token] ||= []
          @unigrams[last_token] << [i, j]

          @bigrams[last_token] ||= {}
          @bigrams[last_token][token] ||= []

          if j == tokens.length-1 # Mark sentence endings
            @unigrams[token] ||= []
            @unigrams[token] << INTERIM
            @bigrams[last_token][token] << INTERIM
          else
            @bigrams[last_token][token] << [i, j+1]
          end

          last_token = token
        end
      end

      self
    end

    def find_token(index)
      if index == INTERIM
        INTERIM
      else
        @sentences[index[0]][index[1]]
      end
    end

    def chain(tokens)
      if tokens.length == 1
        matches = @unigrams[tokens[-1]]
      else
        matches = @bigrams[tokens[-2]][tokens[-1]]
        matches = @unigrams[tokens[-1]] if matches.length < 2
      end

      if matches.empty?
        # This should never happen unless a strange token is
        # supplied from outside the dataset
        raise ArgumentError, "Unable to continue chain for: #{tokens.inspect}"
      end

      next_token = find_token(matches.sample)

      if next_token == INTERIM # We chose to end the sentence
        return tokens
      else
        return chain(tokens + [next_token])
      end
    end

    def generate
      NLP.reconstruct(chain([INTERIM]))
    end
  end
end
