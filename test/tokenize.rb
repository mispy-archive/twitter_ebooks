#!/usr/bin/env ruby
# encoding: utf-8

require 'twitter_ebooks'
require 'minitest/autorun'

module Ebooks
  class TestTokenize < Minitest::Test
    corpus = NLP.normalize(File.read(TEST_CORPUS_PATH))
    sents = NLP.sentences(corpus).sample(10)

    NLP.sentences(corpus).sample(10).each do |sent|
      p sent
      p NLP.tokenize(sent)
      puts
    end
  end
end
