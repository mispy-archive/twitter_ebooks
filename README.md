
## Unmaintained

The Twitter social environment is a bit different than it was when I originally wrote this, and Twitter has [deprecated the streaming API](https://developer.twitter.com/en/docs/accounts-and-users/subscribe-account-activity/api-reference/user-stream) on which the ebooks bots depend. I've moved on to other projects, but feel free to fork!

# twitter\_ebooks

[![Gem Version](https://badge.fury.io/rb/twitter_ebooks.svg)](http://badge.fury.io/rb/twitter_ebooks)
[![Build Status](https://travis-ci.org/mispy/twitter_ebooks.svg)](https://travis-ci.org/mispy/twitter_ebooks)

A framework for building interactive twitterbots which respond to mentions/DMs. See [ebooks_example](https://github.com/mispy/ebooks_example) for a fully-fledged bot definition.

## New in 3.0

- About 80% less memory and storage use for models
- Bots run in their own threads (no eventmachine), and startup is parallelized
- Bots start with `ebooks start`, and no longer die on unhandled exceptions
- `ebooks auth` command will create new access tokens, for running multiple bots
- `ebooks console` starts a ruby interpreter with bots loaded (see Ebooks::Bot.all)
- Replies are slightly rate-limited to prevent infinite bot convos
- Non-participating users in a mention chain will be dropped after a few tweets
- [API documentation](http://rdoc.info/github/mispy/twitter_ebooks) and tests

Note that 3.0 is not backwards compatible with 2.x, so upgrade carefully! In particular, **make sure to regenerate your models** since the storage format changed.

## Installation

Requires Ruby 2.1+. Ruby 2.3+ is recommended.

```bash
gem install twitter_ebooks
```

## Setting up a bot

Run `ebooks new <reponame>` to generate a new repository containing a sample bots.rb file, which looks like this:

``` ruby
# This is an example bot definition with event handlers commented out
# You can define and instantiate as many bots as you like

class MyBot < Ebooks::Bot
  # Configuration here applies to all MyBots
  def configure
    # Consumer details come from registering an app at https://dev.twitter.com/
    # Once you have consumer details, use "ebooks auth" for new access tokens
    self.consumer_key = "" # Your app consumer key
    self.consumer_secret = "" # Your app consumer secret

    # Users to block instead of interacting with
    self.blacklist = ['tnietzschequote']

    # Range in seconds to randomize delay when bot.delay is called
    self.delay_range = 1..6
  end

  def on_startup
    scheduler.every '24h' do
      # Tweet something every 24 hours
      # See https://github.com/jmettraux/rufus-scheduler
      # tweet("hi")
      # pictweet("hi", "cuteselfie.jpg")
    end
  end

  def on_message(dm)
    # Reply to a DM
    # reply(dm, "secret secrets")
  end

  def on_follow(user)
    # Follow a user back
    # follow(user.screen_name)
  end

  def on_mention(tweet)
    # Reply to a mention
    # reply(tweet, meta(tweet).reply_prefix + "oh hullo")
  end

  def on_timeline(tweet)
    # Reply to a tweet in the bot's timeline
    # reply(tweet, meta(tweet).reply_prefix + "nice tweet")
  end

  def on_favorite(user, tweet)
    # Follow user who just favorited bot's tweet
    # follow(user.screen_name)
  end

  def on_retweet(tweet)
    # Follow user who just retweeted bot's tweet
    # follow(tweet.user.screen_name)
  end
end

# Make a MyBot and attach it to an account
MyBot.new("abby_ebooks") do |bot|
  bot.access_token = "" # Token connecting the app to this account
  bot.access_token_secret = "" # Secret connecting the app to this account
end
```

`ebooks start` will run all defined bots in their own threads. The easiest way to run bots in a semi-permanent fashion is with [Heroku](https://www.heroku.com); just make an app, push the bot repository to it, enable a worker process in the web interface and it ought to chug along merrily forever.

The underlying streaming and REST clients from the [twitter gem](https://github.com/sferik/twitter) can be accessed at `bot.stream` and `bot.twitter` respectively.

## Archiving accounts

twitter\_ebooks comes with a syncing tool to download and then incrementally update a local json archive of a user's tweets (in this case, my good friend @0xabad1dea):

``` zsh
➜  ebooks archive 0xabad1dea corpus/0xabad1dea.json
Currently 20209 tweets for 0xabad1dea
Received 67 new tweets
```

The first time you'll run this, it'll ask for auth details to connect with. Due to API limitations, for users with high numbers of tweets it may not be possible to get their entire history in the initial download. However, so long as you run it frequently enough you can maintain a perfect copy indefinitely into the future.

## Text models

In order to use the included text modeling, you'll first need to preprocess your archive into a more efficient form:

``` zsh
➜  ebooks consume corpus/0xabad1dea.json
Reading json corpus from corpus/0xabad1dea.json
Removing commented lines and sorting mentions
Segmenting text into sentences
Tokenizing 7075 statements and 17947 mentions
Ranking keywords
Corpus consumed to model/0xabad1dea.model
```

Notably, this works with both json tweet archives and plaintext files (based on file extension), so you can make a model out of any kind of text.

Text files use newlines and full stops to seperate statements.

Once you have a model, the primary use is to produce statements and related responses to input, using a pseudo-Markov generator:

``` ruby
> model = Ebooks::Model.load("model/0xabad1dea.model")
> model.make_statement(140)
=> "My Terrible Netbook may be the kind of person who buys Starbucks, but this Rackspace vuln is pretty straight up a backdoor"
> model.make_response("The NSA is coming!", 130)
=> "Hey - someone who claims to be an NSA conspiracy"
```

The secondary function is the "interesting keywords" list. For example, I use this to determine whether a bot wants to fav/retweet/reply to something in its timeline:

``` ruby
top100 = model.keywords.take(100)
tokens = Ebooks::NLP.tokenize(tweet.text)

if tokens.find { |t| top100.include?(t) }
  favorite(tweet)
end
```

## Bot niceness

twitter_ebooks will drop bystanders from mentions for you and avoid infinite bot conversations, but it won't prevent you from doing a lot of other spammy things. Make sure your bot is a good and polite citizen!
