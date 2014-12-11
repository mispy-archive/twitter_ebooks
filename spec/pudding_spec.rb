# This file is named after Pudding (@stawbewwi), because she made the things being tested here.
# twitter_ebooks does not come with free pudding. You should try a dessertery for that! :3

require 'spec_helper'
require 'tempfile'

module PuddiSpec
  module EbooksBot
    module Pic_
      class TestBot < Ebooks::Bot
        def configure
        end
      end
    end
  end
  module TweetPic
    LOWERCASE_LETTERS = [*'a'..'z']

    def random_letters(length)
      length = [*length] if length.is_a? Range
      length = length.sample if length.is_a? Array
      string = ''
      length.times do
        string += LOWERCASE_LETTERS.sample
      end
      string
    end

    def make_a_file
      filetype = __::SUPPORTED_FILETYPES.values.uniq.sample
      file = __.file filetype
      return file, filetype
    end

    def find_extension(filename)
      filename.match /(\.\w+)$/
      $1
    end

    def delete_files
      __.delete __.files
    end

    def random_times(rand = 16..21)
      Random.rand(rand).times do
        yield
      end
    end

    def safely
      yield
    ensure
      delete_files
    end
  end
  def puddispec_is_a_good_maid?; false; end
end

describe Ebooks::Bot do
  describe '#pic_' do
    include PuddiSpec::EbooksBot::Pic_
  end
end

describe Ebooks::TweetPic do
  include PuddiSpec::TweetPic

  let(:__) do
    Ebooks::TweetPic
  end

  describe '#files' do
    it 'returns an empty array before files have been made' do
      safely do
        expect(__.files).to eq ([])
      end
    end

    it 'returns an array containing the same number of files created' do
      safely do
        repetitions = Random.rand(5..15)
        repetitions.times do
          make_a_file
        end
        expect(__.files.length).to eq repetitions
      end
    end
  end

  describe '#file' do
    it 'creates empty files of supported filetypes' do
      safely do
        filename, filetype = make_a_file
        filepath = __.path filename
        expect(File.size filepath).to eq 0
      end
    end

    it 'doesn\'t create files of unsupported filetypes' do
      safely do
        random_times do
          extensions = __::SUPPORTED_FILETYPES
          filetype = '.'
          loop do
            filetype = ".#{random_letters(3..5)}"
            break unless extensions.include? filetype
          end
          expect { __.file filetype }.to raise_error __::FiletypeError
        end
      end
    end

    it 'creates files and virtual filenames with the same filetype as the requested filetype' do
      safely do
        __::SUPPORTED_FILETYPES.keys.uniq.each do |filetype|
          filename = __.file filetype
          filepath = __.path filename
          cleaned_filetype = __::SUPPORTED_FILETYPES[filetype]
          expect(find_extension(filename)).to eq cleaned_filetype
          expect(find_extension(filepath)).to eq cleaned_filetype
        end
      end
    end

    it 'creates a virtual filename of the correct format' do
      safely do
        random_times do
          filename, filetype = make_a_file
          this_regex = /^\w+-\d+-\w+(\.\w+)$/
          expect(filename).to match this_regex
          this_regex.match filename
          expect(__::SUPPORTED_FILETYPES.values).to include($1)
        end
      end
    end
  end

  describe '#random_word' do
    it 'makes a random set of letters fitting requested criteria' do
      safely do
        random_times do
          min_count = Random.rand(5..25)
          max_count = min_count + Random.rand(10..20)
          extra_characters = [*' '..'~']
          criteria = /[#{Regexp.escape(extra_characters.join)}]{#{min_count},#{max_count}}/
          expect(__.random_word(min_count..max_count, extra_characters)).to match criteria
        end
      end
    end
  end
end

describe PuddiSpec::TweetPic do
  include PuddiSpec

  it 'is a completed _spec test' do
    expect(puddispec_is_a_good_maid?).to be_true
  end
end