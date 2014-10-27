# -*- encoding: utf-8 -*-
require File.expand_path('../lib/twitter_ebooks/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Jaiden Mispy"]
  gem.email         = ["^_^@mispy.me"]
  gem.description   = %q{Markov chains for all your friends~}
  gem.summary       = %q{Markov chains for all your friends~}
  gem.homepage      = ""

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "twitter_ebooks"
  gem.require_paths = ["lib"]
  gem.version       = Ebooks::VERSION

  gem.add_development_dependency 'rspec'
  gem.add_development_dependency 'memory_profiler'
  gem.add_development_dependency 'pry-byebug'

  gem.add_runtime_dependency 'twitter', '~> 5.0'
  gem.add_runtime_dependency 'simple_oauth', '~> 0.2.0'
  gem.add_runtime_dependency 'tweetstream'
  gem.add_runtime_dependency 'rufus-scheduler'
  gem.add_runtime_dependency 'gingerice'
  gem.add_runtime_dependency 'htmlentities'
  gem.add_runtime_dependency 'engtagger'
  gem.add_runtime_dependency 'fast-stemmer'
  gem.add_runtime_dependency 'highscore'
end
