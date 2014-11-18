require 'spec_helper'
require 'memory_profiler'
require 'tempfile'
require 'timecop'

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

module Ebooks::Test
  # Generates a random twitter id
  def twitter_id
    (rand*10**18).to_i
  end

  # Creates a mock direct message
  # @param username User sending the DM
  # @param text DM content
  def mock_dm(username, text)
    Twitter::DirectMessage.new(id: twitter_id,
                               sender: { id: twitter_id, screen_name: username},
                               text: text)
  end

  # Creates a mock tweet
  # @param username User sending the tweet
  # @param text Tweet content
  def mock_tweet(username, text)
    mentions = text.split.find_all { |x| x.start_with?('@') }
    Twitter::Tweet.new(
      id: twitter_id,
      user: { id: twitter_id, screen_name: username },
      text: text,
      created_at: Time.now.to_s,
      entities: {
        user_mentions: mentions.map { |m|
          { screen_name: m.split('@')[1],
            indices: [text.index(m), text.index(m)+m.length] }
        }
      }
    )
  end

  def simulate(bot, &b)
    bot.twitter = spy("twitter")
    b.call
  end

  def expect_direct_message(bot, content)
    expect(bot.twitter).to have_received(:create_direct_message).with(anything(), content, {})
    bot.twitter = spy("twitter")
  end

  def expect_tweet(bot, content)
    expect(bot.twitter).to have_received(:update).with(content, anything())
    bot.twitter = spy("twitter")
  end
end


describe Ebooks::Bot do
  include Ebooks::Test
  let(:bot) { TestBot.new }

  before { Timecop.freeze }
  after { Timecop.return }

  it "responds to dms" do
    simulate(bot) do
      bot.receive_event(mock_dm("m1sp", "this is a dm"))
      expect_direct_message(bot, "echo: this is a dm")
    end
  end

  it "responds to mentions" do
    simulate(bot) do
      bot.receive_event(mock_tweet("m1sp", "@test_ebooks this is a mention"))
      expect_tweet(bot, "@m1sp echo: this is a mention")
    end
  end

  it "responds to timeline tweets" do
    simulate(bot) do
      bot.receive_event(mock_tweet("m1sp", "some excellent tweet"))
      expect_tweet(bot, "@m1sp fine tweet good sir")
    end
  end

  it "stops mentioning people after a certain limit" do
    simulate(bot) do
      bot.receive_event(mock_tweet("spammer", "@test_ebooks @m1sp 1"))
      expect_tweet(bot, "@spammer @m1sp echo: 1")

      Timecop.travel(Time.now + 60)
      bot.receive_event(mock_tweet("spammer", "@test_ebooks @m1sp 2"))
      expect_tweet(bot, "@spammer @m1sp echo: 2")

      Timecop.travel(Time.now + 60)
      bot.receive_event(mock_tweet("spammer", "@test_ebooks @m1sp 3"))
      expect_tweet(bot, "@spammer echo: 3")
    end
  end

  it "doesn't stop mentioning them if they reply" do
    simulate(bot) do
      bot.receive_event(mock_tweet("spammer", "@test_ebooks @m1sp 4"))
      expect_tweet(bot, "@spammer @m1sp echo: 4")

      Timecop.travel(Time.now + 60)
      bot.receive_event(mock_tweet("m1sp", "@spammer @test_ebooks 5"))
      expect_tweet(bot, "@m1sp @spammer echo: 5")

      Timecop.travel(Time.now + 60)
      bot.receive_event(mock_tweet("spammer", "@test_ebooks @m1sp 6"))
      expect_tweet(bot, "@spammer @m1sp echo: 6")
    end
  end

  it "doesn't get into infinite bot conversations" do
    simulate(bot) do
      bot.receive_event(mock_tweet("spammer", "@test_ebooks @m1sp 7"))
      expect_tweet(bot, "@spammer @m1sp echo: 7")

      Timecop.travel(Time.now + 10)
      bot.receive_event(mock_tweet("spammer", "@test_ebooks @m1sp 8"))
      expect(bot.twitter).to_not have_received(:update)
    end
  end
end
