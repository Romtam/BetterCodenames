# cinch-codenames

This is a fork of an IRC bot using [cinch](https://github.com/cinchrb/cinch), [cinch-game-bot](https://github.com/petertseng/cinch-game-bot) and [codenames](https://github.com/petertseng/codenames).

https://boardgamegeek.com/boardgame/178900

[![Build Status](https://travis-ci.org/Romtam/BetterCodenames.svg?branch=master)](https://travis-ci.org/Romtam/BetterCodenames)

## Setup

You'll need a recent version of [Ruby](https://www.ruby-lang.org/).
Ruby 2.1 or newer is required because of required keyword arguments.

You'll need to install the required gems, which can be done automatically via `bundle install`, or manually by reading the `Gemfile` and using `gem install` on each gem listed.

## Configuration
The settings are located in `/var/lib/gems/2.3.0/gems/codenames-1.0.0/lib/codenames`. Alternatively for this bot it is also located [here](https://github.com/Trigonoculus/codenames)

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
