# twitter\_ebooks 2.3.0

Rewrite of my twitter\_ebooks code. While the original was solely a tweeting Markov generator, this framework helps you build any kind of interactive twitterbot which responds to mentions/DMs. See [ebooks\_example](https://github.com/mispy/ebooks_example) for an example of a full bot.

## Installation

Requires Ruby 1.9.3+ (2.1+ recommended)

```bash
gem install twitter_ebooks
```

## Setting up a bot

Run `ebooks new <reponame>` to generate a new repository containing a sample bots.rb file, which looks like this:

``` ruby
# This is an example bot definition with event handlers commented out
# You can define as many of these as you like; they will run simultaneously

Ebooks::Bot.new("abby_ebooks") do |bot|
  # Consumer details come from registering an app at https://dev.twitter.com/
  # OAuth details can be fetched with https://github.com/marcel/twurl
  bot.consumer_key = "" # Your app consumer key
  bot.consumer_secret = "" # Your app consumer secret
  bot.oauth_token = "" # Token connecting the app to this account
  bot.oauth_token_secret = "" # Secret connecting the app to this account

  bot.on_message do |dm|
    # Reply to a DM
    # bot.reply(dm, "secret secrets")
  end

  bot.on_follow do |user|
    # Follow a user back
    # bot.follow(user[:screen_name])
  end

  bot.on_mention do |tweet, meta|
    # Reply to a mention
    # bot.reply(tweet, meta[:reply_prefix] + "oh hullo")
  end

  bot.on_timeline do |tweet, meta|
    # Reply to a tweet in the bot's timeline
    # bot.reply(tweet, meta[:reply_prefix] + "nice tweet")
  end

  bot.scheduler.every '24h' do
    # Tweet something every 24 hours
    # See https://github.com/jmettraux/rufus-scheduler
    # bot.tweet("hi")
	# bot.pictweet("hi", "cuteselfie.jpg", ":possibly_sensitive => true")
  end
end
```

Bots defined like this can be spawned by executing `run.rb` in the same directory, and will operate together in a single eventmachine loop. The easiest way to run bots in a semi-permanent fashion is with [Heroku](https://www.heroku.com); just make an app, push the bot repository to it, enable a worker process in the web interface and it ought to chug along merrily forever.

The underlying [tweetstream](https://github.com/tweetstream/tweetstream) and [twitter gem](https://github.com/sferik/twitter) client objects can be accessed at `bot.stream` and `bot.twitter` respectively.

## Archiving accounts

twitter\_ebooks comes with a syncing tool to download and then incrementally update a local json archive of a user's tweets.

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
> require 'twitter_ebooks'
> model = Ebooks::Model.load("model/0xabad1dea.model")
> model.make_statement(140)
=> "My Terrible Netbook may be the kind of person who buys Starbucks, but this Rackspace vuln is pretty straight up a backdoor"
> model.make_response("The NSA is coming!", 130)
=> "Hey - someone who claims to be an NSA conspiracy"
```

The secondary function is the "interesting keywords" list. For example, I use this to determine whether a bot wants to fav/retweet/reply to something in its timeline:

``` ruby
top100 = model.keywords.top(100)
tokens = Ebooks::NLP.tokenize(tweet[:text])

if tokens.find { |t| top100.include?(t) }
  bot.twitter.favorite(tweet[:id])
end
```

## Other notes

If you're using Heroku, which has no persistent filesystem, automating the process of archiving, consuming and updating can be tricky. My current solution is just a daily cron job which commits and pushes for me, which is pretty hacky.
