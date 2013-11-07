#!/usr/bin/env ruby
# encoding: utf-8

require 'twitter_ebooks'
require 'minitest/autorun'
require 'benchmark'

module Ebooks
  class TestKeywords < Minitest::Test
    corpus = NLP.normalize(File.read(ARGV[0]))
    puts "Finding and ranking keywords"
    puts Benchmark.measure {
      NLP.keywords(corpus).top(50).each do |keyword|
        puts "#{keyword.text} #{keyword.weight}"
      end
    }
  end
end
