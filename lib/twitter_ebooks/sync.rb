#!/usr/bin/env ruby
# encoding: utf-8

require 'twitter'
require 'json'
require 'mini_magick'
require 'open-uri'
require 'pry'

module Ebooks
  class Sync

    def self.run(botname, username)
      bot = Ebooks::Bot.get(botname)
      bot.configure
      source_user = username
      ebooks_user = bot.username
      user = bot.twitter.user(source_user)
      if user.profile_image_url then
        Ebooks::Sync::get(user.profile_image_url(:original), "image/#{source_user}_avatar")
        avatar = MiniMagick::Image.open("image/#{source_user}_avatar")
        avatar.flip
        avatar.write("image/#{ebooks_user}_avatar")
        avatar64 = Base64.encode64(File.read("image/#{ebooks_user}_avatar"))
        bot.twitter.update_profile_image(avatar64)
        p "Updated profile image for #{ebooks_user} from #{source_user}."
      else
        p "#{source_user} does not have a profile image to clone."
      end
      if user.profile_banner_url then
        Ebooks::Sync::get(user.profile_banner_url, "image/#{source_user}banner")
        banner = MiniMagick::Image.open("image/#{source_user}banner")
        banner.flip
        banner.write("image/#{ebooks_user}_banner")
        banner64 = Base64.encode64(File.read("image/#{ebooks_user}_banner"))
        bot.twitter.update_profile_banner(banner64)
        p "Updated cover image for #{ebooks_user} from #{source_user}."
      else
        p "#{source_user} does not have a cover image to clone."
      end
    end

    def self.get(url, destination)
      File.open(destination, "wb") do |saved_file|
        open(url, "rb") do |read_file|
          saved_file.write(read_file.read)
        end
      end
    end

  end
end
