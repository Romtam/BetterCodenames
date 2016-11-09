require 'cinch'
require 'cinch/plugins/game_bot'
require 'codenames/game'
require 'codenames/text'

module Cinch; module Plugins; class Codenames < GameBot
  include Cinch::Plugin

  match(/teams?(?:\s+(a|b|r|x))?/i, method: :team)
  match(/words(?:\s+(##?\w+))?/i, method: :words)
  match(/history(?:\s+(##?\w+))?/i, method: :history)

  match(/me$/i, method: :become_hinter)
  match(/rand(?:om)?$/i, method: :random_hinter)

  match(/h(?:int)?\s+(\S+)(?:\s+(\S+))?/i, method: :hint)
  match(/c(?:lue)?\s+(\S+)(?:\s+(\S+))?/i, method: :hint)

  match(/g(?:uess)?\s+(.+)/i, method: :guess)

  # We don't want !status to accidentally trigger !s, or the like.
  match(/s$|p$/i, method: :no_guess)
  match(/stop/i, method: :no_guess)
  match(/pass/i, method: :no_guess)
  match(/noguess/i, method: :no_guess)

  match(/help(?: (.+))?/i, method: :help)
  match(/rules/i, method: :rules)
  match(/foo/i, method: :foo)
  match(/peek(?:\s+(##?\w+))?/i, method: :peek)

  add_common_commands

  TEAMS = [
    [:bold, :blue, 'Team Blue'],
    [:bold, :red, 'Team Red'],
  ]
  NEUTRAL = 'Civilian'
  ASSASSIN = 'Assassin'

  def initialize(*args)
    super
    # Game strips out whitespace, but just to be sure!
    possible_words = config[:words_file] ? IO.readlines(config[:words_file]).map(&:chomp) : config[:words]
    ::Codenames::Game.possible_words = possible_words
  end

  #--------------------------------------------------------------------------------
  # Implementing classes should override these
  #--------------------------------------------------------------------------------

  def min_players; ::Codenames::Game::MIN_PLAYERS end
  def max_players; ::Codenames::Game::MAX_PLAYERS end
  def game_name; ::Codenames::Game::GAME_NAME end

  def do_start_game(m, channel_name, players, settings, start_args)
    players_and_preferences = players.map { |p| [p.user, p.data[:team_preference]] }.to_h
    begin
      game = ::Codenames::Game.new(channel_name, players_and_preferences)
    rescue => e
      m.reply("Failed to start game because #{e}", true)
      return
    end

    chan = Channel(game.channel_name)
    chan.send("Welcome to game #{game.id}")
    teams_and_players = game.teams.map { |team|
      "#{format_team(team.id)}: #{team.users.map(&:nick).join(', ')}"
    }.join(' and ')
    chan.send("The teams for game #{game.id} are #{teams_and_players}")

    if game.current_phase == :choose_hinter
      chan.send("All teams: please have one player volunteer to be #{::Codenames::Text::ROLES[:hint]} (!me) or randomly decide (!random).")
    else
      self.send_initial_info(game)
    end

    game
  end

  def do_reset_game(game)
    return unless game.teams.all?(&:picked_roles?)
    Channel(game.channel_name).send(self.endgame_word_info(game))
  end

  def do_replace_user(game, replaced_user, replacing_user)
    # I don't think we need to do anything.
  end

  #game_status aliased to decision_info later

  #--------------------------------------------------------------------------------
  # Game
  #--------------------------------------------------------------------------------

  def become_hinter(m)
    self.choose_hinter(m)
  end

  def random_hinter(m)
    self.choose_hinter(m, random: true)
  end

  def choose_hinter(m, random: false)
    game = self.game_of(m)
    return unless game

    role_name = ::Codenames::Text::ROLES[:hint]

    # Actually if success == true then error is a boolean,
    # but I don't even need to rely on that.
    success, error = game.choose_hinter(m.user, random: random)
    if success
      # Is it OK to highlight the previous hinters when a new hinter is picked?
      # Well, a new hinter being picked always moves the game along, then yes.
      # We can revisit this if it turns out to be a problem later.
      m.reply(game.teams.select(&:picked_roles?).map { |team|
        hinters = team.hinters.map(&:nick)
        "#{format_team(team.id)}'s #{role_name}#{hinters.size == 1 ? ' is' : 's are'} #{hinters.join(', ')}"
      }.join(' and '))
    else
      m.reply("Failed to choose #{role_name} because #{error}", true)
    end

    # If all hinters have been chosen, move the game along.
    self.send_initial_info(game) if game.teams.all?(&:picked_roles?)
  end

  def hint(m, word, num)
    game = self.game_of(m)
    return unless game

    success, error = game.hint(m.user, word, num)
    if success
      chan = Channel(game.channel_name)
      chan.send(self.public_word_info(game))
      chan.send(decision_info(game))
    else
      m.reply("Failed to give clue because #{error}", true)
    end
  end

  def guess(m, guessed)
    game = self.game_of(m)
    return unless game

    # Save these because they could change after guess is done.
    team_name = format_team(game.current_team_id)
    other_team = game.teams[game.other_team_id]

    success, error = game.guess(m.user, guessed)

    if success
      chan = Channel(game.channel_name)
      guess_info = error

      prefix = "#{m.user} of #{team_name} contacted #{guessed.strip.capitalize}"
      case guess_info.role
      when :assassin
        chan.send("#{prefix} the #{ASSASSIN}! #{team_name} loses!")
        self.congratulate_winners(game)
      when :neutral
        chan.send("#{prefix} the #{NEUTRAL}. #{team_name}'s turn is over.")
        self.prompt_hinters(game, other_team.hinters)
      when Integer
        if guess_info.winner
          chan.send("#{prefix} the #{format_team(guess_info.role)} agent! #{format_team(guess_info.winner)} has found all their agents!")
          self.congratulate_winners(game)
        else
          what_next = guess_info.turn_ends ? "#{team_name}'s turn is over." : "#{team_name} can continue guessing."
          chan.send("#{prefix} the #{format_team(guess_info.role)} agent. #{what_next}")
          if guess_info.turn_ends
            self.prompt_hinters(game, other_team.hinters)
          else
            chan.send(decision_info(game))
          end
        end
      else
        chan.send("Unknown word type #{guess_info.role}, unclear how to proceed.")
        chan.send(decision_info(game))
      end
    else
      m.reply("Failed to guess because #{error}", true)
    end
  end

  def no_guess(m)
    game = self.game_of(m)
    return unless game

    success, error = game.no_guess(m.user)
    if success
      # At this point current_team is no longer the passing team.
      # It's the team who needs to give a hint, so current_team is correct.
      self.prompt_hinters(game, game.current_team.hinters)
    else
      m.reply("Failed to pass on guessing because #{error}", true)
    end
  end

  def team(m, arg = nil)
    # Game started: show teams.
    if (game = self.game_of(m))
      game.teams.each { |team|
        if team.picked_roles?
          msg = [:hint, :guess].map { |role|
            users = team.with_role(role)
            role_name = "#{::Codenames::Text::ROLES[role]}#{'s' if users.size != 1}"
            "#{format_team(team.id)} #{role_name}: #{users.map { |u| dehighlight_nick(u.nick) }.join(', ')}"
          }.join(', ')
        else
          msg = "#{format_team(team.id)}: #{team.users.map { |u| dehighlight_nick(u.nick) }.join(', ')}"
        end
        m.reply(msg)
      }
      return
    end

    waiting_room = self.waiting_room_of(m)

    if arg
      # Not started and arg given: change team preference.
      case arg.downcase
      when 'a'; team = 0
      when 'b'; team = 1
      else; team = nil
      end
      waiting_room.data[m.user][:team_preference] = team
      team_name = team ? 'AB'[team] : 'Random'
      m.reply("You joined team #{team_name}.", true)
    else
      # Not started and no arg: show teams.
      prefs = waiting_room.players.group_by { |p| p.data[:team_preference] }
      return if prefs.empty?
      team_ids = (0...::Codenames::Game::NUM_TEAMS).to_a
      team_ids << nil
      # We're not mapping over prefs[i] because I want this specific order.
      teams = team_ids.map { |i|
        next nil unless prefs[i] && !prefs[i].empty?
        team_name = i ? 'AB'[i] : 'Random'
        "Team #{team_name} (#{prefs[i].size}): #{prefs[i].map { |p| dehighlight_nick(p.user.nick) }.join(', ')}"
      }.compact.join(', ')
      m.reply(teams)
    end
  end

  def words(m, channel_name = nil)
    game = self.game_of(m, channel_name, ['see words', '!words'])
    return unless game

    # We don't show words until everyone has chosen roles.
    return unless game.teams.all?(&:picked_roles?)

    if game.role_of(m.user) == :hint
      m.user.send(self.hinter_word_info(game))
    else
      m.reply(self.public_word_info(game))
    end
  end

  def history(m, channel_name = nil)
    game = self.game_of(m, channel_name, ['see history', '!history'])
    return unless game

    if game.hints.empty?
      m.reply("Game #{game.id} history: Nothing yet!")
      return
    end

    m.reply("Game #{game.id} history:\n" + game.hints.map { |entry|
      prefix = "#{format_team(entry.team)} Hint: #{entry.to_s}. Guesses: "
      next "#{prefix}None yet." if entry.guesses.empty?

      # The first N-1 guesses must be the right team (so that the team could continue guessing),
      # so we just need to check the role of the last word.
      last_role = entry.guesses.last.role
      team_results = entry.guesses.size - 1
      team_results += 1 if last_role == entry.team

      guess_roles = []
      guess_roles << "#{team_results} #{format_team(entry.team)}" if team_results > 0
      guess_roles << "1 #{NEUTRAL}" if last_role == :neutral
      # Assassin probably not possible, but maybe one day we'll have retroactive history.
      guess_roles << "1 #{ASSASSIN}" if last_role == :assassin
      guess_roles << "1 #{format_team(last_role)}" if last_role.is_a?(Integer) && last_role != entry.team

      guesses = entry.guesses.map { |g| g.word.capitalize }.join(', ')

      "#{prefix}#{guesses} (#{guess_roles.join(', ')})."
    }.join("\n"))
  end

  def peek(m, channel_name = nil)
    return unless self.is_mod?(m.user)
    game = self.game_of(m, channel_name, ['peek', '!peek'])
    return unless game

    if game.users.include?(m.user)
      m.user.send('Cheater!!!')
      return
    end

    m.user.send(self.endgame_word_info(game))
  end

  #--------------------------------------------------------------------------------
  # Help for player/table info
  #--------------------------------------------------------------------------------

  def send_initial_info(game)
    hinter_info = self.hinter_word_info(game)
    game.teams.each { |team| team.hinters.each { |hinter| hinter.send(hinter_info) } }
    chan = Channel(game.channel_name)
    chan.send("Codenames for game #{game.id}: #{game.public_words[:unguessed].map(&:capitalize).join(', ')}")
    chan.send(decision_info(game))
  end

  def prompt_hinters(game, hinters)
    hinter_info = self.hinter_word_info(game)
    hinters.each { |hinter| hinter.send(hinter_info) }
    Channel(game.channel_name).send(decision_info(game))
  end

  def congratulate_winners(game)
    chan = Channel(game.channel_name)
    chan.send("Congratulations!!! #{game.winning_players.map(&:nick).join(', ')} are the winners!") if game.winning_players
    chan.send(self.endgame_word_info(game))
    self.start_new_game(game)
  end

  def decision_info(game)
    info = case game.current_phase
    when :choose_hinter
      teams_left = game.teams.reject(&:picked_roles?)
      teams_and_players = teams_left.map { |team|
        "#{format_team(team.id)} (#{team.users.map(&:nick).join(', ')})"
      }.join(' and ')

      "#{teams_and_players} #{teams_left.size == 1 ? 'is' : 'are'} choosing a #{::Codenames::Text::ROLES[:hint]}"
    when :hint, :guess
      role = game.current_phase
      team = game.current_team
      players = team.with_role(role)
      intro = "#{format_team(team.id)} #{::Codenames::Text::ROLES[role]}#{'s' if players.size != 1} (#{players.map(&:nick).join(', ')})"
      instructions = if role == :hint
        'Please present a !clue to your team: one word and one number indicating how many codenames are related to the word (or "unlimited").'
      else
        can_stop = game.guessed_this_turn? ? ' or !stop guessing' : ''
        guesses = game.guesses_remaining
        guesses = 'unlimited' if guesses == Float::INFINITY
        "Please make a !guess for the clue \"#{game.current_hint}\"#{can_stop}. You have #{guesses} guess#{'es' if guesses != 1} remaining."
      end
      "#{intro}: #{instructions}"
    end
    "Game #{game.id} turn #{game.turn_number}: #{info}"
  end
  alias :game_status :decision_info

  def classify_one(name, words, max, show_max: true)
    max_str = show_max ? "/#{max}" : ''
    "#{name}#{'s' if max != 1} (#{words.size}#{max_str}): #{words.map(&:capitalize).join(', ')}"
  end

  def classify_words(words, show_max: true)
    lines = []
    ::Codenames::Game::NUM_TEAMS.times { |i|
      if (agents = words[i])
        max = ::Codenames::Game::TEAM_WORDS[i]
        lines << classify_one("#{format_team(i)} agent", agents, max, show_max: show_max)
      end
    }
    if (neutrals = words[:neutral])
      lines << classify_one(NEUTRAL, neutrals, ::Codenames::Game::NEUTRAL_WORDS, show_max: show_max)
    end
    if (assassins = words[:assassin])
      lines << classify_one(ASSASSIN, assassins, ::Codenames::Game::ASSASSIN_WORDS, show_max: show_max)
    end
    lines
  end

  def public_word_info(game)
    words = game.public_words
    lines = ["Game #{game.id} turn #{game.turn_number} status:"]
    lines.concat(classify_words(words[:guessed]))
    lines << "Unidentified (#{words[:unguessed].size}): #{words[:unguessed].map(&:capitalize).join(', ')}"
    lines.join("\n")
  end

  def hinter_word_info(game)
    words = game.hinter_words
    lines = ["Game #{game.id} turn #{game.turn_number} status:"]
    lines.concat(classify_words(words, show_max: false))
    lines.join("\n")
  end

  def endgame_word_info(game)
    words = game.hinter_words(exclude_revealed: false)
    lines = ["Game #{game.id} words:"]
    lines.concat(classify_words(words, show_max: false))
    lines.join("\n")
  end

  def format_team(id)
    Format(*TEAMS[id])
  end

  #--------------------------------------------------------------------------------
  # General
  #--------------------------------------------------------------------------------

  def help(m, page = '')
    page ||= ''
    page = '' if page.strip.downcase == 'mod' && !self.is_mod?(m.user)
    case page.strip.downcase
    when 'mod'
      m.reply('Cheating: peek')
      m.reply('Game admin: kick, reset, replace')
    when '2'
      m.reply("Set team (pre-game): team")
      m.reply("Game info: team, words, status")
      m.reply("Game actions: guess (alias g), clue (alias c, hint, h), stop (alias s, pass, p, noguess)")
    when '3'
      m.reply('Getting people to play: invite, subscribe, unsubscribe')
      m.reply('To get PRIVMSG: notice off. To get NOTICE: notice on')
    else
      m.reply("General help: All commands can be issued by '!command' or '#{m.bot.nick}: command' or PMing 'command'")
      m.reply('General commands: join, leave, start, who')
      m.reply('Game-related commands: help 2. Preferences: help 3')
    end
  end

  def rules(m)
    m.reply('https://boardgamegeek.com/filepage/119841/codenames-rulebook-english')
  end

  # Test command
  def foo(m)
    m.reply('bar')
  end

end; end; end
