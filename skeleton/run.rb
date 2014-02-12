#!/usr/bin/env ruby

require_relative 'bots'

EM.run do
 Ebooks::Bot.all.each do |bot|
    bot.start
  end
end
