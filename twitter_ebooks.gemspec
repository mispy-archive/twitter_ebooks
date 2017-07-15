# -*- encoding: utf-8 -*-
require File.expand_path('../lib/twitter_ebooks/version', __FILE__)

Gem::Specification.new do |gem|
  gem.required_ruby_version = '~> 2.1'

  gem.authors       = ["Jaiden Mispy"]
  gem.email         = ["^_^@mispy.me"]
  gem.description   = %q{Markov chains for all your friends~}
  gem.summary       = %q{Markov chains for all your friends~}
  gem.homepage      = "https://github.com/mispy/twitter_ebooks"

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "twitter_ebooks"
  gem.require_paths = ["lib"]
  gem.version       = Ebooks::VERSION
  gem.licenses      = ["MIT"]

  gem.add_development_dependency 'rspec', '~> 3.6'
  gem.add_development_dependency 'rspec-mocks', '~> 3.6'
  gem.add_development_dependency 'memory_profiler', '~> 0.9'
  gem.add_development_dependency 'timecop', '~> 0.9'
  gem.add_development_dependency 'pry-byebug', '~> 3.4'
  gem.add_development_dependency 'yard', '~> 0.9'

  gem.add_runtime_dependency 'twitter', '~> 6.1'
  gem.add_runtime_dependency 'rufus-scheduler', '~> 3.4'
  gem.add_runtime_dependency 'gingerice', '~> 1.2'
  gem.add_runtime_dependency 'htmlentities', '~> 4.3'
  gem.add_runtime_dependency 'engtagger', '~> 0'
  gem.add_runtime_dependency 'fast-stemmer', '~> 1.0'
  gem.add_runtime_dependency 'highscore', '~> 1.2'
  gem.add_runtime_dependency 'pry', '~> 0'
  gem.add_runtime_dependency 'oauth', '~> 0.5'
  gem.add_runtime_dependency 'mini_magick', '~> 4.8'
end
