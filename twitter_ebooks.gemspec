# -*- encoding: utf-8 -*-
require File.expand_path('../lib/twitter_ebooks/version', __FILE__)

Gem::Specification.new do |gem|
  gem.required_ruby_version = '~> 2.1'

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
  gem.add_development_dependency 'rspec-mocks'
  gem.add_development_dependency 'memory_profiler'
  gem.add_development_dependency 'timecop'
  gem.add_development_dependency 'pry-byebug'
  gem.add_development_dependency 'yard'

  gem.add_runtime_dependency 'twitter', '~> 5.15'
  gem.add_runtime_dependency 'rufus-scheduler'
  gem.add_runtime_dependency 'gingerice'
  gem.add_runtime_dependency 'htmlentities'
  gem.add_runtime_dependency 'engtagger'
  gem.add_runtime_dependency 'fast-stemmer'
  gem.add_runtime_dependency 'highscore'
  gem.add_runtime_dependency 'pry'
  gem.add_runtime_dependency 'oauth'
  gem.add_runtime_dependency 'mini_magick'
end
