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
      repeats = Random.rand(rand)
      repeats.times do
        yield
      end
      repeats
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

  after :each do
    delete_files
  end

  describe '#files' do
    it 'returns an empty array before files have been made' do
      expect(__.files).to eq ([])
    end

    it 'returns an array containing the same number of files created' do
      repetitions = random_times do
        make_a_file
      end
      expect(__.files.length).to eq repetitions
    end
  end

  describe '#file' do
    it 'creates empty files of supported filetypes' do
      filename, filetype = make_a_file
      filepath = __.path filename
      expect(File.size filepath).to eq 0
    end

    it 'doesn\'t create files of unsupported filetypes' do
      extensions = __::SUPPORTED_FILETYPES
      filetype = '.'
      loop do
        filetype = ".#{random_letters(3..5)}"
        break unless extensions.include? filetype
      end
      expect { __.file filetype }.to raise_error __::FiletypeError
    end

    it 'creates files and virtual filenames with the same filetype as the requested filetype' do
      __::SUPPORTED_FILETYPES.keys.uniq.each do |filetype|
        filename = __.file filetype
        filepath = __.path filename
        cleaned_filetype = __::SUPPORTED_FILETYPES[filetype]
        expect(find_extension(filename)).to eq cleaned_filetype
        expect(find_extension(filepath)).to eq cleaned_filetype
      end
    end

    it 'creates a virtual filename of the correct format' do
      random_times do
        filename, filetype = make_a_file
        this_regex = /^\w+-\d+-\w+(\.\w+)$/
        expect(filename).to match this_regex
        this_regex.match filename
        expect(__::SUPPORTED_FILETYPES.values).to include($1)
      end
    end
  end

  describe '#random_word' do
    it 'makes a random set of letters fitting requested criteria' do
      random_times do
        min_count = Random.rand(5..25)
        max_count = min_count + Random.rand(10..20)
        extra_characters = [*' '..'~']
        criteria = /[#{Regexp.escape(extra_characters.join)}]{#{min_count},#{max_count}}/
        expect(__.random_word(min_count..max_count, extra_characters)).to match criteria
      end
    end
  end

  describe '#fetch' do
    it 'raises an error when a file doesn\'t exist' do
      expect do
        __.fetch random_letters 5..25
      end.to raise_error __::NoSuchFileError
    end

    it 'returns a file object' do
      name, ext = make_a_file
      expect(__.fetch name).to be_a File
    end

    it 'returns the same file' do
      name, ext = make_a_file
      file = __.fetch name
      random_text = random_letters 32..64
      File.open file.path, 'w' do |this_file|
        this_file.write random_text
      end
      newfile = __.fetch name
      expect(newfile).to be file
      expect(File.read newfile.path).to eq random_text
    end
  end

  describe '#path' do
    it 'provides the same path as the one gotten from #fetch' do
      name, ext = make_a_file
      file = __.fetch name
      expect(__.path name).to eq file.path
    end
  end

  describe '#scheduler' do
    it 'gives a scheduler' do
      expect(__.scheduler).to be_a Rufus::Scheduler
    end

    it 'gives the same scheduler' do
      scheduler = __.scheduler
      expect(__.scheduler).to be scheduler
    end
  end

  describe '#delete' do
    it 'can delete files successfully' do
      random_times do
        make_a_file
      end
      __.delete __.files
      expect(__.files).to be_empty
    end

    it 'deletes the right files' do
      random_times do
        make_a_file
      end
      delete_file = __.files.sample
      __.delete delete_file
      expect(__.files).not_to include delete_file
    end
  end
end

describe PuddiSpec::TweetPic do
  include PuddiSpec

  it 'is a completed _spec test' do
    expect(puddispec_is_a_good_maid?).to be_true
  end
end