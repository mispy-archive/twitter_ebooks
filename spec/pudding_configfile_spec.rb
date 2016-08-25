# This file is named after Pudding (@stawbewwi), because she made the things being tested here.
# twitter_ebooks does not come with free pudding. You should try a dessertery for that! :3

require 'spec_helper'
require 'tempfile'

module PuddiSpec
  module ConfigFile
    class TestBot < Ebooks::Bot
      def configure
      end
    end

    def ask(config_file)
      if File.absolute_path(config_file) == config_file
        @PuddiSpec_current_test_bot = TestBot.new config_file
      else
        @PuddiSpec_current_test_bot = TestBot.new path(config_file)
      end
    end

    def hello
      @PuddiSpec_current_test_bot = TestBot.new random_string 1..15
    end

    def my
      @PuddiSpec_current_test_bot.config
    end
    alias_method :my_hash, :my

    def expect_me
      expect(my)
    end

    def please
      @PuddiSpec_current_test_bot
    end

    def me_to_try(format, data)
      case format
      when 'yaml'
        require 'yaml'
        data = data.to_yaml
      when 'json'
        require 'json'
        data = data.to_json
      else
        return
      end
      @PuddiSpec_current_testing_file = Tempfile.new ['spec', '.' + format]
      @PuddiSpec_current_testing_file.write data
      @PuddiSpec_current_testing_file.close
      @PuddiSpec_current_testing_file.path
    end

    ALPHA_CHARACTERS = [*'0'..'9', *'a'..'z', *'A'..'Z']
    CAP_CHARACTERS = [*'A'..'Z']

    def random_string(length, extra_char = [])
      length = [*length] if length.is_a? Range
      length = length.sample if length.is_a? Array
      characters = ALPHA_CHARACTERS | extra_char
      [*1..length].map! do |i|
        characters.sample
      end.join
    end

    def random_upcase(length, extra_char = [])
      length = [*length] if length.is_a? Range
      length = length.sample if length.is_a? Array
      characters = CAP_CHARACTERS | extra_char
      [*1..length].map! do |i|
        characters.sample
      end.join
    end

    def simple_hash
      {random_string(5..15) => random_string(10..25)}
    end

    def generate_twitter(force_username_special_char = false)
      return_hash = {'twitter' => {}}
      twitter_hash = return_hash['twitter']

      username = random_string 1..15
      if force_username_special_char
        username[Random.rand(username.length)] = '_'
        username = "@#{username}"
      end
      twitter_hash['username'] = username

      twitter_hash['consumer key'] = random_string 50..70
      twitter_hash['consumer secret'] = random_string 115..140
      twitter_hash['access token'] = random_string(12..15) + '-' + random_string(85..110)
      twitter_hash['access token secret'] = random_string 105..125

      return_hash
    end

    def expect_twitter_authed_with(twitter_hash)
      sub_hash = twitter_hash['twitter']
      username = sub_hash['username']
      username = username[1..-1] if username && username.start_with?('@')
      expect(please.username).to eq username if username
      expect(please.consumer_key).to eq sub_hash['consumer key'] if sub_hash['consumer key']
      expect(please.consumer_secret).to eq sub_hash['consumer secret'] if sub_hash['consumer secret']
      expect(please.access_token).to eq sub_hash['access token'] if sub_hash['access token']
      expect(please.access_token_secret).to eq sub_hash['access token secret'] if sub_hash['access token secret']
    end

    def run_before
      @PuddiSpec_environment_variables = ENV.invert
    end

    def run_after
      @PuddiSpec_current_testing_file.close! if @PuddiSpec_current_testing_file
      @PuddiSpec_environment_variables.delete_if do |value, key|
        ENV[key] = value
        true
      end
    end
  end
end

describe Ebooks::Bot do
  describe '#config' do
    include PuddiSpec::ConfigFile

    before :each do
      run_before
    end

    after :each do
      run_before
    end

    it 'returns the same hash every time' do
      hello
      expect_me.to eq my_hash
    end

    it 'can parse yaml' do
      this_hash = simple_hash
      ask me_to_try 'yaml', this_hash
      expect_me.to eq this_hash
    end

    it 'can parse json' do
      this_hash = simple_hash
      ask me_to_try 'json', this_hash
      expect_me.to eq this_hash
    end

    it 'can read twitter details from yaml' do
      twitter_hash = generate_twitter
      ask me_to_try 'yaml', twitter_hash
      expect_twitter_authed_with twitter_hash
    end

    it 'can read twitter details from json' do
      twitter_hash = generate_twitter
      ask me_to_try 'json', twitter_hash
      expect_twitter_authed_with twitter_hash
    end

    it 'can read twitter details from env variables' do
      env_suffix = random_upcase 1..15
      if_this_works = env_suffix.downcase + '.env'
      twitter_hash = generate_twitter
      ENV["EBOOKS_USERNAME_#{env_suffix}"] = twitter_hash['twitter']['username']
      ENV["EBOOKS_CONSUMER_KEY_#{env_suffix}"] = twitter_hash['twitter']['consumer key']
      ENV["EBOOKS_CONSUMER_SECRET_#{env_suffix}"] = twitter_hash['twitter']['consumer secret']
      ENV["EBOOKS_ACCESS_TOKEN_#{env_suffix}"] = twitter_hash['twitter']['access token']
      ENV["EBOOKS_ACCESS_TOKEN_SECRET_#{env_suffix}"] = twitter_hash['twitter']['access token secret']
      ask if_this_works
      expect_twitter_authed_with twitter_hash
    end

    it 'is fine with twitter usernames starting with @ and containing _' do
      twitter_hash = generate_twitter true
      ask me_to_try 'yaml', twitter_hash
      expect_twitter_authed_with twitter_hash
    end

    it 'doesn\'t mind loading just consumer key and secret' do
      twitter_hash = generate_twitter
      twitter_hash['twitter'].delete('username')
      twitter_hash['twitter'].delete('access token')
      twitter_hash['twitter'].delete('access token secret')
      ask me_to_try 'yaml', twitter_hash
      expect_twitter_authed_with twitter_hash
    end

    it 'can\'t be easily edited after creation' do
      ask me_to_try 'yaml', {1=>{2=>{3=>{4=>{5=>{6=>{7=>{8=>{9=>10}}}}}}}}}
      expect do
        my[1] = 0
      end.to raise_error
      expect do
        my[1][2] = 0
      end.to raise_error
      expect do
        my[1][2][3] = 0
      end.to raise_error
      expect do
        my[1][2][3][4] = 0
      end.to raise_error
      expect do
        my[1][2][3][4][5] = 0
      end.to raise_error
      expect do
        my[1][2][3][4][5][6] = 0
      end.to raise_error
      expect do
        my[1][2][3][4][5][6][7] = 0
      end.to raise_error
      expect do
        my[1][2][3][4][5][6][7][8] = 0
      end.to raise_error
      expect do
        my[1][2][3][4][5][6][7][8][9] = 0
      end.to raise_error
    end

    it 'doesn\'t throw an exception when given a file that doesn\'t actually exist' do
      ask 'are you okay with non existent files.yaml'
      expect_me.to eq ({})
    end
  end
end