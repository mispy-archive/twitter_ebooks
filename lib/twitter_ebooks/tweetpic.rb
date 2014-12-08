# encoding: utf-8
require 'rufus/scheduler'
require 'net/http'
require 'tempfile'

module Ebooks
  class Bot
    # Tweet something containing an image
    # Only four images are allowed per tweet, but you can pass as many as you want
    # The first four to be uploaded sucessfully will be included in your tweet
    # Provide a block if you would like to modify your files before they're uploaded.
    # @param tweet_text [String] text content for tweet
    # @param pic_list [String, Array<String>] a string or array of strings containing pictures to tweet
    # @param tweet_options [Hash] options hash that will be passed along with your tweet
    # @param upload_options [Hash] options hash passed while uploading images
    # @yield [file_name] provides full filenames of files after they have been fetched, but before they're uploaded to twitter
    def pic_tweet(tweet_text, pic_list, tweet_options = {}, upload_options = {}, &block)
      tweet_options ||= {}
      upload_options ||= {}
      
      tweet_options.merge! Ebooks::TweetPic.process(self, pic_list, upload_options, block)
      tweet(tweet_text, tweet_options)
    end
    alias_method :pictweet, :pic_tweet

    # Reply to a tweet with a message containing an image. MAY work with dms.
    # Only four images are allowed per tweet, but you can pass as many as you want
    # The first four to be uploaded sucessfully will be included in your tweet
    # Provide a block if you would like to modify your files before they're uploaded.
    # @param reply_tweet [Twitter::Tweet, Twitter::DirectMessage] tweet or direct message to reply to. direct messages are untested.
    # @param (see #pic_tweet)
    # @yield (see #pic_tweet)
    # @todo test if this works with DMs
    def pic_reply(reply_tweet, tweet_text, pic_list, tweet_options = {}, upload_options = {}, &block)
      tweet_options ||= {}
      upload_options ||= {}
      
      tweet_options.merge! Ebooks::TweetPic.process(self, pic_list, upload_options, block)
      reply(reply_tweet, tweet_text, tweet_options)
    end
    alias_method :picreply, :pic_reply
  end

  # A singleton that uploads pictures to twitter for tweets and stuff
  module TweetPic
    # Default directory name
    DIRECTORY = 'tweet_pic_temp'
    private_constant :DIRECTORY

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
    HTTPResponseError = Class.new IOError
    FiletypeError = Class.new TypeError
    EmptyFileError = Class.new IOError
    NoUploadedFilesError = Class.new RuntimeError

    # Singleton
    class << self
      # Find directory name
      # @param directory_name [String] Set name of directory. Only does anything if a directory hasn't been made yet.
      # @return [String] name of directory
      def directory(directory_name = DIRECTORY)
        directory_name ||= DIRECTORY

        # Generate a directory name if it doesn't exist.
        unless defined? @directory_variable
          # Start out just trying to make a directory with the base name
          @directory_variable = directory_name
          current_count = 0

          # Keep looking for a folder that doesn't exist yet
          while File.exists?(@directory_variable)
            # If a folder exists, but it's empty, that's fine.
            break if Dir.exists?(pictweet_temp_folder) && Dir.entries(pictweet_temp_folder).length < 3
            # Otherwise, add 1 and keep looking.
            @directory_variable = "#{directory_name}_#{current_count.to_s}"
            current_count += 1
          end
        end

        # Create directory if it doesn't currently exist (can happen a lot).
        Dir.mkdir(@directory_variable) unless Dir.exists? @directory_variable

        @directory_variable
      end
      private :directory

      # Next file name
      # @param file_extension [String] file extension to append to filename
      # @return [String] new filename
      # @raise [Ebooks::TweetPic::FiletypeError] if extension isn't one supported by Twitter
      def file(file_extension = '')
        file_extension ||= ''

        # Add a dot if it doesn't already
        file_extension.prepend('.') unless file_extension.start_with? '.'

        # Make file_extension lowercase if it isn't already
        file_extension.downcase!

        # Raise an error if the file-extension isn't supported.
        raise FiletypeError, "'#{file_extension}' isn't as supported filetype" unless SUPPORTED_FILETYPES.has_key? file_extension

        # Increment file name
        @file_variable = @file_variable.to_i.next
        "#{@file_variable}#{file_extension}"
      end

      # Creates a scheduler
      # @return [Rufus::Scheduler]
      def scheduler
        @scheduler_variable ||= Rufus::Scheduler.new
      end
      private :scheduler

      # Find files inside directory
      # @note not to be confused with {::file}
      # @return [Array<String>] array of filenames inside directory
      def files
        # Return an empty array if directory hasn't even been made yet
        return [] unless defined? @directory_variable

        # Otherwise, return everything inside directory, minus dot elements.
        Dir.entries(directory) - ['.', '..']
      end

      # Queues a file for deletion, deletes all queued files if possible, and then deletes folder if it's empty.
      # @param trash_files [Array<String>] files to queue for deletion
      # @return [Array<String>] files still in deletion queue
      def delete(trash_files = [])
        trash_files ||= []

        # Create queue if necesscary
        @delete_queue ||= []
        # Merge trash_files into queue
        @delete_queue &= trash_files
        # Compare queue to files that are actually in directory
        @delete_queue |= files

        # Iterate through delete_queue
        @delete_queue.delete_if do |current_file|
          begin
            # Attempt to delete file
            File.delete "#{directory}/#{current_file}"
          rescue
            # Deleting file failed. Just move on.
            next false
          end
        end

        unless @delete_queue.empty?
          # Schedule another deletion in a minute.
          scheduler.in('1m') do
            delete
          end
        end

        # Remove directory if it's empty now.
        Dir.rmdir(directory) if files.empty?

        @delete_queue
      end

      # Downloads a file into directory
      # @param uri_string [String] uri of image to download
      # @return [String] filename of downloaded file
      # @raise [Ebooks::TweetPic::HTTPResponseError] if any http response other than code 200 is received
      # @raise [Ebooks::TweetPic::FiletypeError] if content-type isn't one supported by Twitter
      # @raise [Ebooks::TweetPic::EmptyFileError] if downloaded file is empty for some reason
      def download(uri_string)
        # Create URI object to download file with
        uri_object = URI(uri_string)
        # Create a local variable for file name
        destination_filename = ''
        full_destination_filename = ''
        # Open download thingie
        Net::HTTP.start(uri_object.host, uri_object.port) do |http_object|
          http_object.request Net::HTTP::Get.new(uri_object) do |response_object|
            # Cancel if something goes wrong.
            raise HTTPResponseError, "'#{uri_string}' caused HTTP Error #{response_object.code}: #{response_object.msg}" unless response_object.code == '200'
            # Check file format
            content_type = response_object['content-type']
            if SUPPORTED_FILETYPES.has_key? content_type
              destination_filename = file SUPPORTED_FILETYPES[content_type]
              full_destination_filename = "#{directory}/#{destination_filename}"
            else
              raise FiletypeError, "'#{uri_string}' is an unsupported content-type: '#{content_type}'"
            end

            # Now write to file!
            open(full_destination_filename, 'w') do |file|
              response_object.read_body do |chunk|
                file.write chunk
              end
            end
          end
        end
        # If filesize is empty, something went wrong.
        downloaded_filesize = File.size(full_destination_filename)
        raise EmptyFileError, "'#{uri_string}' produced an empty file" if downloaded_filesize == 0

        # If we survived this long, everything is all set!
        destination_filename
      end
      private :download

      # Copies a file into directory
      # @param source_filename [String] relative path of image to copy
      # @return [String] filename of copied file
      def copy(source_filename)
        # Find file-extension
        if source_filename.match /(\.\w+)$/
          file_extension = $1
        end

        # Create destination filename
        destination_filename = file file_extension

        # Do copying
        FileUtils.copy(source_filename, "#{directory}/#{destination_filename}")

        destination_filename
      end
      private :copy

      # Puts a file into directory, downloading or copying as necesscary
      # @param source_file [String] relative path or internet address of image
      # @return [String] filename of file in directory
      def get(source_file)
        # Is source_file a url?
        if source_file.match /^https?:\/\//i # Starts with http(s)://, case insensitive
          download(source_file)
        else
          copy(source_file)
        end
      end

      # Allows editing of files through a block.
      # @param file_list [Array<String>] names of files to edit
      # @yield [file_name] provides full filenames of files for block to manipulate
      def edit(file_list, &block)
        # This method doesn't do anything without a block
        return unless block_given?

        # First, make sure file_list actually contains actual files.
        file_list &= files

        # Iterate over files, giving their full filenames over to the block
        file_list.each do |file_list_each|
          yield "#{directory}/#{file_list_each}"
        end
      end

      # Upload an image file to Twitter
      # @param twitter_object [Twitter] a twitter object to upload file with
      # @param file_name [String] name of file to upload
      # @return [Integer] media id from twitter
      def upload(twitter_object, file_name, upload_options = {})
        upload_options ||= {}

        # Open file stream
        file_object = File.new "#{directory}/#{file_name}"
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
      # @todo See if this is is available via API, or edit this if it ever changes
      def limit(*args)
        tweet_picture_limit = 4

        case args.length
        when 0
          tweet_picture_limit
        when 1
          if args[0].respond_to? :length
            args[0].length - tweet_picture_limit
          else
            raise ArgumentError, "undefined method 'length' for #{args[0].class.to_s}"
          end
        else
          raise ArgumentError, "Incorrect number of arguments: expected 0 or 1, got #{args.length}"
        end
      end

      # Gets media ids parameter ready for a tweet
      # @param bot_object [Ebooks::Bot] an ebooks bot to upload files with
      # @param pic_list [String, Array<String>] an array of relative paths or uris to upload, or a string if there's only one
      # @param upload_options [Hash] options hash passed while uploading images
      # @param [Proc] a proc meant to be passed to {::edit}
      # @return [Hash{Symbol=>String}] A hash containing a single :media_ids key/value pair for update options
      # @raise [Ebooks::TweetPic::NoUploadedFilesError] if no files in pic_list could be uploaded
      def process(bot_object, pic_list, upload_options, block)
        # If pic_list isn't an array, make it one.
        pic_list = [pic_list] unless pic_list.is_a? Array

        # If pic_list is an empty array or an array containing an empty string, just return an empty hash. People know what they're doing, right?
        return {} if pic_list == [] or pic_list == ['']

        # Create an array to store media IDs from Twitter
        successful_images = []
        uploaded_media_ids = []

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
            edit([temporary_path], &block)
            # Upload image to Twitter
            uploaded_media_ids << upload(bot_object.twitter, temporary_path, upload_options)
            # If we made it this far, we've pretty much succeeded
            successful_images << source_path
            # Delete image. It's okay if this fails.
            delete([temporary_path])
          rescue
            # If something went wrong, just skip on. No need to log anything.
            next
          end
        end

        raise NoUploadedFilesError, 'None of images provided could be uploaded.' if uploaded_media_ids.empty?

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