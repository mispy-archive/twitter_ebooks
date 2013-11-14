gem 'minitest'

def log(*args)
  STDERR.puts args.map(&:to_s).join(' ')
  STDERR.flush
end

module Ebooks
  GEM_PATH = File.expand_path(File.join(File.dirname(__FILE__), '..'))
  DATA_PATH = File.join(GEM_PATH, 'data')
  SKELETON_PATH = File.join(GEM_PATH, 'skeleton')
  TEST_PATH = File.join(GEM_PATH, 'test')
  TEST_CORPUS_PATH = File.join(TEST_PATH, 'corpus/0xabad1dea.tweets')
end

require 'twitter_ebooks/nlp'
require 'twitter_ebooks/archiver'
require 'twitter_ebooks/markov'
require 'twitter_ebooks/suffix'
require 'twitter_ebooks/model'
require 'twitter_ebooks/bot'
