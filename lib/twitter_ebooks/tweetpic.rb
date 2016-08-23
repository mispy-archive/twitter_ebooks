# encoding: utf-8
require 'rufus/scheduler'
require 'open-uri'
require 'tempfile'

module Ebooks
  class Bot
    # Tweet something containing an image
    # Only four images are allowed per tweet, but you can pass as many as you want
    # The first four to be uploaded sucessfully will be included in your tweet
    # Provide a block if you would like to modify your files before they're uploaded
    # @param tweet_text [String] text content for tweet
    # @param pic_list [String, Array<String>] a string or array of strings containing pictures to tweet
    #   provide only a file extension to create an empty file of that type. this won't work unless you also provide a block to generate imgaes.
    # @param tweet_options [Hash] options hash that will be passed along with your tweet
    # @param upload_options [Hash] options hash passed while uploading images
    # @yield [file_name] provides full filenames of files after they have been fetched, but before they're uploaded to twitter
    # @raise [StandardError] first exception, if no files could be uploaded
    def pic_tweet(tweet_text, pic_list, tweet_options = {}, upload_options = {}, &block)
      tweet_options ||= {}
      upload_options ||= {}

      media_options = Ebooks::TweetPic.process self, pic_list, upload_options, &block

      tweet tweet_text, tweet_options.merge(media_options)
    end
    alias_method :pictweet, :pic_tweet

    # Reply to a tweet with a message containing an image. Does not work with DMs
    # Only four images are allowed per tweet, but you can pass as many as you want
    # The first four to be uploaded sucessfully will be included in your tweet
    # Provide a block if you would like to modify your files before they're uploaded
    # @param reply_tweet [Twitter::Tweet, Twitter::DirectMessage] tweet to reply to
    # @param (see #pic_tweet)
    # @yield (see #pic_tweet)
    # @raise (see #pic_tweet)
    # @raise [ArgumentError] if reply_tweet is a direct message
    def pic_reply(reply_tweet, tweet_text, pic_list = nil, tweet_options = {}, upload_options = {}, &block)
      pic_list ||= meta(reply_tweet).media_uris('large')

      tweet_options ||= {}
      upload_options ||= {}

      raise ArgumentError, 'reply_tweet can\'t be a direct message' if reply_tweet.is_a? Twitter::DirectMessage

      media_options = Ebooks::TweetPic.process self, pic_list, upload_options, &block

      reply reply_tweet, tweet_text, tweet_options.merge(media_options)
    end
    alias_method :picreply, :pic_reply

    # Does the same thing as {#pic_reply}, but doesn't do anything if pic_list is empty.
    # Safe to place directly inside reply with no checks for media beforehand.
    # @param (see #pic_reply)
    # @yield (see #pic_reply)
    def pic_reply?(reply_tweet, tweet_text, pic_list = nil, tweet_options = {}, upload_options = {}, &block)
      pic_list ||= meta(reply_tweet).media_uris('large')

      unless pic_list.empty?
        pic_reply reply_tweet, tweet_text, pic_list, tweet_options, upload_options, &block
      end
    end
  end

  # A singleton that uploads pictures to twitter for tweets and stuff
  module TweetPic
    # Default file prefix
    DEFAULT_PREFIX = 'tweet-pic'
    private_constant :DEFAULT_PREFIX

    # Characters for random string generation
    RANDOM_CHARACTERS = [*'a'..'z', *'A'..'Z', *'1'..'9', '_']

    # Supported filetypes and their extensions
    SUPPORTED_FILETYPES = {
      '.jpg' => '.jpg',
      '.jpeg' => '.jpg',
      'image/jpeg' => '.jpg',
      '.png' => '.png',
      'image/png' => '.png',
      '.gif' => '.gif',
      'image/gif' => '.gif'
    }

    # Exceptions
    Error = Class.new RuntimeError
    FiletypeError = Class.new Error
    EmptyFileError = Class.new Error
    NoSuchFileError = Class.new Error

    # Singleton
    class << self

      # List all files inside virtual directory
      # @note not to be confused with {#file}
      # @return [Array<String>] array of filenames inside virtual directory
      def files
        # Return an empty array if file hash hasn't even been made yet
        return [] unless defined? @file_hash

        # Otherwise, return everything
        @file_hash.keys
      end

      # Create a new file inside virtual directory
      # @param file_extension [String] file extension to append to filename
      # @return [String] new virtual filename
      # @raise [Ebooks::TweetPic::FiletypeError] if extension isn't one supported by Twitter
      def file(file_extension)
        # Try to find an appropriate filetype.
        catch :extension_found do
          # Make file_extension lowercase if it isn't already
          file_extension.downcase
          # Does it already match?
          if SUPPORTED_FILETYPES.has_key? file_extension
            # It does, so standardize our file extension
            file_extension = SUPPORTED_FILETYPES[file_extension]
            throw :extension_found
          end
          # It doesn't. Is it missing a .?
          unless file_extension.start_with? '.'
            # Add it in
            file_extension.prepend('.')
            # Try again
            if SUPPORTED_FILETYPES.has_key? file_extension
              # Found it now!
              file_extension = SUPPORTED_FILETYPES[file_extension]
              throw :extension_found
            end
          end
          # File-extension isn't supported.
          raise FiletypeError, "'#{file_extension}' isn't a supported filetype"
        end

        # Create file hash if it doesn't exist yet.
        @file_hash ||= {}

        # Increment file name
        virtual_filename = @file_variable = @file_variable.to_i.next

        # Make a filename, adding on a random part to make it harder to find
        virtual_filename = "#{random_word 7..13}-#{virtual_filename}-#{random_word 13..16}"

        # Do we have a prefix yet?
        @file_prefix ||= "#{DEFAULT_PREFIX}-#{Time.now.to_f.to_s.gsub(/\./, '-')}"

        # Create a new real file(name)
        real_file = Tempfile.create(["#{@file_prefix}-#{virtual_filename}-", file_extension])
        real_file.close

        # Store virtual filename and realfile into file_hash
        full_virtual_filename = "#{virtual_filename}#{file_extension}"
        @file_hash[full_virtual_filename] = real_file

        full_virtual_filename
      ensure
        # Ensure that it's not left open, no matter what happens.
        real_file.close if real_file.respond_to?(:close) && !real_file.closed?
      end
      private :file

      # Create a random string of word characters (filename friendly)
      # @param character_number_array [Integer, Range<Integer>, Array<Integer, Range<Integer>>] number of characters to generate.
      #   types including multiple integers will pick a random one.
      # @param extra_characters [Array<String>] extra characters
      # @return [String] random string with length asked for
      def random_word(character_number_array, extra_characters = [])
        extra_characters ||= []

        # If it's not an array, make it one.
        character_number_array = [character_number_array] unless character_number_array.is_a? Array
        # Make a new array to hold expanded stuff
        number_of_characters = []
        # Iterate through array
        character_number_array.each do |element|
          if element.is_a? Range
            # It's a range, so expand it and add it to number_of_characters
            number_of_characters |= [*element]
          else
            # It's not a range, so just add it.
            number_of_characters << element
          end
        end

        # Get our actual number
        number_of_characters = number_of_characters.uniq.sample
        # Create array with random characters.
        extra_characters = RANDOM_CHARACTERS | extra_characters
        # Create a string to hold characters in
        random_string = ''
        # Repeat this number_of_characters times
        number_of_characters.times do
          # Add another character to string
          random_string += extra_characters.sample
        end

        random_string
      end
      private :random_word

      # Fetch a file object
      # @param virtual_filename [String] object to look for
      # @return [Tempfile] file object
      # @raise [Ebooks::TweetPic::NoSuchFileError] if file doesn't actually exist
      def fetch(virtual_filename)
        raise NoSuchFileError, "#{virtual_filename} doesn't exist" unless @file_hash.has_key? virtual_filename

        @file_hash[virtual_filename]
      end
      private :fetch

      # Get a real path for a virtual filename
      # @param (see ::fetch)
      # @return [String] path of file
      # @raise (see ::fetch)
      def path(virtual_filename)
        fetch(virtual_filename).path
      end
      private :path

      # Creates a scheduler
      # @return [Rufus::Scheduler]
      def scheduler
        @scheduler_variable ||= Rufus::Scheduler.new
      end
      private :scheduler

      # Queues a file for deletion and deletes all queued files if possible
      # @param trash_files [String, Array<String>] files to queue for deletion
      # @return [Array<String>] files still in deletion queue
      def delete(trash_files = [])
        trash_files ||= []

        # Turn trash_files into an array if it isn't one.
        trash_files = [trash_files] unless trash_files.is_a? Array

        # Create queue if necesscary
        @delete_queue ||= []
        # Iterate over trash files
        trash_files.each do |trash_item|
          # Retrieve trash_item's real path
          file_object = @file_hash.delete trash_item
          # Was trash_item in hash?
          unless file_object.nil?
            # It was. Add it to queue
            @delete_queue << file_object.path
          end
        end

        # Make sure there aren't duplicates
        @delete_queue.uniq!

        # Iterate through delete_queue
        @delete_queue.delete_if do |current_file|
          begin
            # Attempt to delete file if it exists
            File.delete current_file if File.file? current_file
          rescue
            # Deleting file failed. Just move on.
            false
          else
            true
          end
        end

        unless @delete_queue.empty?
          # Schedule another deletion in a minute.
          scheduler.in('1m') do
            delete
          end
        end

        @delete_queue
      end

      # Downloads a file into directory
      # @param uri_string [String] uri of image to download
      # @return [String] filename of downloaded file
      # @raise [Ebooks::TweetPic::FiletypeError] if content-type isn't one supported by Twitter
      # @raise [Ebooks::TweetPic::EmptyFileError] if downloaded file is empty for some reason
      def download(uri_string)
        # Make a variable to hold filename
        destination_filename = ''

        # Prepare to return an error if file is empty
        empty_file_detector = lambda { |file_size| raise EmptyFileError, "'#{uri_string}' produced an empty file" if file_size == 0 }
        # Grab file off the internet. open-uri will provide an exception if this errors.
        URI(uri_string).open(content_length_proc: empty_file_detector) do |downloaded_file|
          content_type = downloaded_file.content_type
          if SUPPORTED_FILETYPES.has_key? content_type
            destination_filename = file SUPPORTED_FILETYPES[content_type]
          else
            raise FiletypeError, "'#{uri_string}' is an unsupported content-type: '#{content_type}'"
          end

          # Everything seems okay, so write to file.
          File.open path(destination_filename), 'w' do |opened_file|
            until downloaded_file.eof?
              opened_file.write downloaded_file.read 1024
            end
          end
        end

        # If we haven't exited from an exception yet, so everything is fine!
        destination_filename
      end
      private :download

      # Copies a file into directory
      # @param source_filename [String] relative path of image to copy or an extension for an empty file
      # @return [String] filename of copied file
      def copy(source_filename)
        file_extension = ''

        # Find file-extension
        if match_data = source_filename.match(/(\.\w+)$/)
          file_extension = match_data[1]
        end

        # Create destination filename
        destination_filename = file file_extension

        # Do copying, but just leave empty if source_filename is just an extension
        FileUtils.copy(source_filename, path(destination_filename)) unless source_filename == file_extension

        destination_filename
      end
      private :copy

      # Puts a file into directory, downloading or copying as necesscary
      # @param source_file [String] relative path or internet address of image
      # @return [String] filename of file in directory
      def get(source_file)
        # Is source_file a url?
        if source_file =~ /^(ftp|https?):\/\//i # Starts with http(s)://, case insensitive
          download(source_file)
        else
          copy(source_file)
        end
      end

      # Allows editing of files through a block.
      # @param file_list [String, Array<String>] names of files to edit
      # @yield [file_name] provides full filenames of files for block to manipulate
      # @raise [Ebooks::TweetPic::NoSuchFileError] if files don't exist
      # @raise [ArgumentError] if no block is given
      def edit(file_list, &block)
        # Turn file_list into an array if it's not an array
        file_list = [file_list] unless file_list.is_a? Array

        # First, make sure file_list actually contains actual files.
        file_list &= files

        # Raise if we have no files to work with
        raise NoSuchFileError, 'Files don\'t exist' if file_list.empty?

        # This method doesn't do anything without a block
        raise ArgumentError, 'block expected but none given' unless block_given?

        # Iterate over files, giving their full filenames over to the block
        file_list.each do |file_list_each|
          yield path(file_list_each)
        end
      end

      # Upload an image file to Twitter
      # @param twitter_object [Twitter] a twitter object to upload file with
      # @param file_name [String] name of file to upload
      # @return [Integer] media id from twitter
      # @raise [Ebooks::TweetPic::EmptyFileError] if file is empty
      def upload(twitter_object, file_name, upload_options = {})
        upload_options ||= {}

        # Does file exist, and is it empty?
        raise EmptyFileError, "'#{file_name}' is empty" if File.size(path(file_name)) == 0
        # Open file stream
        file_object = File.open path(file_name)
        # Upload it
        media_id = twitter_object.upload(file_object, upload_options)
        # Close file stream
        file_object.close

        media_id
      end

      # @overload limit()
      #   Find number of images permitted per tweet
      #   @return [Integer] number of images permitted per tweet
      # @overload limit(check_list)
      #   Check if a list's length is equal to, less than, or greater than limit
      #   @param check_list [#length] object to check length of
      #   @return [Integer] difference between length and the limit, with negative values meaning length is below limit.
      def limit(check_list = nil)
        # Twitter's API page just says, "You may associated[sic] up to 4 media to a Tweet," with no information on how to dynamically get this value.
        tweet_picture_limit = 4

        if check_list
          check_list.length - tweet_picture_limit
        else
          tweet_picture_limit
        end
      end

      # Gets media ids parameter ready for a tweet
      # @param bot_object [Ebooks::Bot] an ebooks bot to upload files with
      # @param pic_list [String, Array<String>] an array of relative paths or uris to upload, or a string if there's only one
      # @param upload_options [Hash] options hash passed while uploading images
      # @param [Proc] a proc meant to be passed to {#edit}
      # @return [Hash{Symbol=>String}] A hash containing a single :media_ids key/value pair for update options
      # @raise [StandardError] first error if no files in pic_list could be uploaded
      def process(bot_object, pic_list, upload_options, &block)
        # If pic_list isn't an array, make it one.
        pic_list = [pic_list] unless pic_list.is_a? Array

        # If pic_list is an empty array or an array containing an empty string, just return an empty hash. People know what they're doing, right?
        return {} if pic_list == [] or pic_list == ['']

        # Create an array to store media IDs from Twitter
        successful_images = []
        uploaded_media_ids = []

        first_exception = nil

        # Iterate over picture list
        pic_list.each do |pic_list_each|
          # Stop now if uploaded_media_ids is long enough.
          break if limit(uploaded_media_ids) >= 0

          # This entire block is wrapped in a rescue, so we can skip over things that went wrong. Errors will be dealt with later.
          begin
            # Make current image a string, just in case
            source_path = pic_list_each.to_s
            # Fetch image
            temporary_path = get(source_path)
            # Allow people to modify image
            edit(temporary_path, &block) if block_given?
            # Upload image to Twitter
            uploaded_media_ids << upload(bot_object.twitter, temporary_path, upload_options)
            # If we made it this far, we've pretty much succeeded
            successful_images << source_path
            # Delete image. It's okay if this fails.

            delete(temporary_path)
          rescue => exception
            # If something went wrong, just skip on. No need to log anything.
            first_exception ||= exception
          end
        end

        raise first_exception if uploaded_media_ids.empty?

        # This shouldn't be necessary, but trim down array if it needs to be.
        successful_images = successful_images[0...limit] unless limit(successful_images) < 0
        uploaded_media_ids = uploaded_media_ids[0...limit] unless limit(uploaded_media_ids) < 0

        # Report that we just uploaded images to log
        successful_images_joined = successful_images.join ' '
        bot_object.log "Uploaded to Twitter: #{successful_images_joined}"

        # Return options hash
        {:media_ids => uploaded_media_ids.join(',')}
      end
    end
  end
end
