require 'spec_helper'
require 'memory_profiler'
require 'tempfile'
require 'timecop'

class TestBot < Ebooks::Bot
  attr_accessor :twitter

  def configure
  end

  def on_message(dm)
    reply dm, "echo: #{dm.text}"
  end

  def on_mention(tweet)
    reply tweet, "echo: #{meta(tweet).mentionless}"
  end

  def on_timeline(tweet)
    reply tweet, "fine tweet good sir"
  end
end

module Ebooks::Test
  # Generates a random twitter id
  # Or a non-random one, given a string.
  def twitter_id(seed = nil)
    if seed.nil?
      (rand*10**18).to_i
    else
      id = 1
      seed.downcase.each_byte do |byte|
        id *= byte/10
      end
      id
    end
  end

  # Creates a mock direct message
  # @param username User sending the DM
  # @param text DM content
  def mock_dm(username, text)
    Twitter::DirectMessage.new(id: twitter_id,
                               sender: { id: twitter_id(username), screen_name: username},
                               text: text)
  end

  # Creates a mock tweet
  # @param username User sending the tweet
  # @param text Tweet content
  def mock_tweet(username, text, extra={})
    mentions = text.split.find_all { |x| x.start_with?('@') }
    tweet = Twitter::Tweet.new({
      id: twitter_id,
      in_reply_to_status_id: 'mock-link',
      user: { id: twitter_id(username), screen_name: username },
      text: text,
      created_at: Time.now.to_s,
      entities: {
        user_mentions: mentions.map { |m|
          { screen_name: m.split('@')[1],
            indices: [text.index(m), text.index(m)+m.length] }
        }
      }
    }.merge!(extra))
    tweet
  end

  # Creates a mock user
  def mock_user(username)
    Twitter::User.new(id: twitter_id(username), screen_name: username)
  end

  def twitter_spy(bot)
    twitter = spy("twitter")
    allow(twitter).to receive(:update).and_return(mock_tweet(bot.username, "test tweet"))
    allow(twitter).to receive(:user).with(no_args).and_return(mock_user(bot.username))
    twitter
  end

  def simulate(bot, &b)
    bot.twitter = twitter_spy(bot)
    bot.update_myself # Usually called in prepare
    b.call
  end

  def expect_direct_message(bot, content)
    expect(bot.twitter).to have_received(:create_direct_message).with(anything(), content, {})
    bot.twitter = twitter_spy(bot)
  end

  def expect_tweet(bot, content)
    expect(bot.twitter).to have_received(:update).with(content, anything())
    bot.twitter = twitter_spy(bot)
  end
end


describe Ebooks::Bot do
  include Ebooks::Test
  let(:bot) { TestBot.new('Test_Ebooks') }

  before { Timecop.freeze }
  after { Timecop.return }

  it "responds to dms" do
    simulate(bot) do
      bot.receive_event(mock_dm("m1sp", "this is a dm"))
      expect_direct_message(bot, "echo: this is a dm")
    end
  end

  it "ignores its own dms" do
    simulate(bot) do
      expect(bot).to_not receive(:on_message)
      bot.receive_event(mock_dm("Test_Ebooks", "why am I talking to myself"))
    end
  end

  it "responds to mentions" do
    simulate(bot) do
      bot.receive_event(mock_tweet("m1sp", "@test_ebooks this is a mention"))
      expect_tweet(bot, "@m1sp echo: this is a mention")
    end
  end

  it "ignores its own mentions" do
    simulate(bot) do
      expect(bot).to_not receive(:on_mention)
      expect(bot).to_not receive(:on_timeline)
      bot.receive_event(mock_tweet("Test_Ebooks", "@m1sp i think that @test_ebooks is best bot"))
    end
  end

  it "responds to timeline tweets" do
    simulate(bot) do
      bot.receive_event(mock_tweet("m1sp", "some excellent tweet"))
      expect_tweet(bot, "@m1sp fine tweet good sir")
    end
  end

  it "ignores its own timeline tweets" do
    simulate(bot) do
      expect(bot).to_not receive(:on_timeline)
      bot.receive_event(mock_tweet("Test_Ebooks", "pudding is cute"))
    end
  end

  it "links tweets to conversations correctly" do
    tweet1 = mock_tweet("m1sp", "tweet 1", id: 1, in_reply_to_status_id: nil)

    tweet2 = mock_tweet("m1sp", "tweet 2", id: 2, in_reply_to_status_id: 1)

    tweet3 = mock_tweet("m1sp", "tweet 3", id: 3, in_reply_to_status_id: nil)

    bot.conversation(tweet1).add(tweet1)
    expect(bot.conversation(tweet2)).to eq(bot.conversation(tweet1))

    bot.conversation(tweet2).add(tweet2)
    expect(bot.conversation(tweet3)).to_not eq(bot.conversation(tweet2))
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

      Timecop.travel(Time.now + 2)
      bot.receive_event(mock_tweet("spammer", "@test_ebooks @m1sp 8"))
      expect_tweet(bot, "@spammer @m1sp echo: 8")

      Timecop.travel(Time.now + 2)
      bot.receive_event(mock_tweet("spammer", "@test_ebooks @m1sp 9"))
      expect(bot.twitter).to_not have_received(:update)
    end
  end

  it "blocks blacklisted users on contact" do
    simulate(bot) do
      bot.blacklist = ["spammer"]
      bot.receive_event(mock_tweet("spammer", "@test_ebooks @m1sp 7"))
      expect(bot.twitter).to have_received(:block).with("spammer")
    end
  end
end
