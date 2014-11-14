require 'spec_helper'
require 'memory_profiler'
require 'tempfile'

def Process.rss; `ps -o rss= -p #{Process.pid}`.chomp.to_i; end

class TestBot < Ebooks::Bot
  attr_accessor :twitter

  def configure
    self.username = "test_ebooks"
  end

  def on_direct_message(dm)
    reply dm, "echo: #{dm.text}"
  end

  def on_mention(tweet, meta)
    reply tweet, "echo: #{meta[:mentionless]}"
  end

  def on_timeline(tweet, meta)
    reply tweet, "fine tweet good sir"
  end
end

def twitter_id
  533295311591337984
end

def mock_dm(username, text)
  Twitter::DirectMessage.new(id: twitter_id,
                             sender: { id: twitter_id, screen_name: username},
                             text: text)
end

def mock_tweet(username, text)
  mentions = text.split.find_all { |x| x.start_with?('@') }
  Twitter::Tweet.new(
    id: twitter_id,
    user: { id: twitter_id, screen_name: username },
    text: text,
    entities: {
      user_mentions: mentions.map { |m|
        { screen_name: m.split('@')[1],
          indices: [text.index(m), text.index(m)+m.length] }
      }
    }
  )
end

describe Ebooks::Bot do
  let(:bot) { TestBot.new }

  it "responds to dms" do
    bot.twitter = double("twitter")
    expect(bot.twitter).to receive(:create_direct_message).with("m1sp", "echo: this is a dm", {})
    bot.receive_event(mock_dm("m1sp", "this is a dm"))
  end

  it "responds to mentions" do
    bot.twitter = double("twitter")
    expect(bot.twitter).to receive(:update).with("@m1sp echo: this is a mention",
                                                 in_reply_to_status_id: twitter_id)
    bot.receive_event(mock_tweet("m1sp", "@test_ebooks this is a mention"))
  end

  it "responds to timeline tweets" do
    bot.twitter = double("twitter")
    expect(bot.twitter).to receive(:update).with("@m1sp fine tweet good sir",
                                                 in_reply_to_status_id: twitter_id)

    bot.receive_event(mock_tweet("m1sp", "some excellent tweet"))
  end
end
