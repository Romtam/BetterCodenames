# cinch-codenames

This is a fork of an IRC bot using [cinch](https://github.com/cinchrb/cinch), [cinch-game-bot](https://github.com/petertseng/cinch-game-bot) and [codenames](https://github.com/petertseng/codenames).

https://boardgamegeek.com/boardgame/178900

[![Build Status](https://travis-ci.com/Romtam/BetterCodenames.svg?token=jU2bRcL1YsgdnFvuP8Xt&branch=master)](https://travis-ci.com/Romtam/BetterCodenames)

## Setup

You'll need a recent version of [Ruby](https://www.ruby-lang.org/).
Ruby 2.1 or newer is required because of required keyword arguments.
The [build status](https://travis-ci.org/petertseng/cinch-codenames) will confirm compatibility with various Ruby versions.
Note that [2.1 is in security maintenance mode](https://www.ruby-lang.org/en/news/2016/02/24/support-plan-of-ruby-2-0-0-and-2-1/), so it would be better to use a later version.

You'll need to install the required gems, which can be done automatically via `bundle install`, or manually by reading the `Gemfile` and using `gem install` on each gem listed.

## Usage

Given that you have performed the requisite setup, the minimal code to get a working bot might resemble:

```ruby
require 'cinch'
require 'cinch/plugins/codenames'

bot = Cinch::Bot.new do
  configure do |c|
    c.nick            = 'CodenamesBot'
    c.server          = 'irc.example.org'
    c.channels        = ['#playcodenames']
    c.plugins.plugins = [Cinch::Plugins::Codenames]
    c.plugins.options[Cinch::Plugins::Codenames] = {
      channels: ['#playcodenames'],
      settings: 'codenames-settings.yaml',
    }
  end
end

bot.start
```
