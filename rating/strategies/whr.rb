require 'date'
require File.expand_path("glicko", File.dirname(__FILE__))
require File.expand_path("../system/", File.dirname(__FILE__))

# WHR requires a lot of state for each player
# Here are some classes to hold that state
# Actual WHR module below


# Abstract out what rating scale the ratings are on
class Rating
  attr_accessor :elo
  def initialize(elo=nil)
    @elo = elo
    return self
  end
  def gamma=(gamma)
    @elo = 400.0*Math::log10(gamma)
    return self
  end
  def gamma()
    return 10**(@elo/400.0)
  end
  def aga_rating=(aga_rating)
    @elo = ::Glicko::set_aga_rating({}, aga_rating).rating
    return self
  end
end

# Each player has a list of these objects, one for each day the player has games
class PlayerDay
  attr_accessor :day, :games, :r, :wins, :player
  def initialize(day, player)
    @day = day
    @games    = []       # list of games
    @r        = Rating.new(0.0)
    @wins     = 0.0
    @player   = player
  end
  def numgames()
    return @games.length
  end
  def winrate()
    return -1.0 if @games.length == 0
    return @wins / @games.length
  end
end

class WHR_Player
  attr_accessor :vpd, :name, :prior_initialized, :num_win, :num_loss, :anchor_R, :prior_games
  def initialize(name, anchor_R=nil)
    @vpd = []       # List of PlayerDay objects, must be in chronological order
    @name = name
    @prior_initialized = false
    @num_win = 0
    @num_loss = 0
    if anchor_R != nil
      @anchor_R = anchor_R.dup()   # Anchor player's rating
    else
      @anchor_R = nil
    end
    @prior_games = []  # Virtual games on the first player day to avoid all wins / all losses spiraling
  end
  def getVpd(day)
    for vpd in @vpd
      return vpd if vpd.day == day
    end
    raise "Day %d not found in player %s" % day, @name
  end
  def addNewVpd(day)
    if (@vpd != [])
      raise "Days assumed to be chronological" unless @vpd[-1].day < day
    end
    @vpd.push(PlayerDay.new(day, self))
    @vpd[-1].r = @anchor_R.dup() if @anchor_R
  end
  def addPrior(day)
    # Add two virtual games against the _PRIOR_ANCHOR on the first day
    @prior_games = [Game.new(day, self, ::PDB[:prior_anchor], self                , WHR::PRIOR_WEIGHT),
                    Game.new(day, self, ::PDB[:prior_anchor], ::PDB[:prior_anchor], WHR::PRIOR_WEIGHT)]
    for game in @prior_games
      # Use the first vpd for each player
      # It's a bit strange to use only first vpd for the _PRIOR_ANCHOR, 
      #   but it doesn't matter and it's easier
      if ::PDB[:prior_anchor].vpd == []
         ::PDB[:prior_anchor].addNewVpd(day)
      end
      game.white_player_vpd = @vpd[0]
      game.black_player_vpd = ::PDB[:prior_anchor].vpd[0]
    end
  end
  def addGame(game)
    if @vpd == [] or @vpd[-1].day != game.day
      if @name[0].class != Symbol or @vpd == []  # Only use one vpd for special Symbol players
        self.addNewVpd(game.day)
      end
    end
    if not @prior_initialized
      self.addPrior(game.day)
      @prior_initialized = true
    end
    @vpd[-1].games.push(game)
    if game.winner == self
      @vpd[-1].wins += 1.0
    end
    return @vpd[-1]  # return link to the vpd used
  end
  def tostring(verbose=0)
    s = @name
    for vpd in @vpd
      s += "\n" if verbose > 0
      s += vpd.r.tostring()
      if verbose >= 1
        s += " day=%s numgames=%d winrate=%0.3f" % [vpd.day, vpd.numgames(), vpd.winrate()]
        if verbose >= 2
          for game in vpd.games
            if game.winner == self then s += " W"
            else                        s += " L" end
          end
        end
      end
    end
    return s
  end
  def mostRecentRating()
    return -1.0 if @vpd == []
    return @vpd[-1].r.elo
  end
  # Hack these in for ::Glicko to be happy
  def rating()
    return mostRecentRating()
  end
  def rd()
    return 33  # Bogus somewhat small rd value
  end
end


class Game
  attr_accessor :day, :white_player, :black_player, :winner, :weight, :black_player_vpd, :white_player_vpd
  def initialize(day, white_player, black_player, winner, weight=1.0)
     raise "Invalid winner" if winner != white_player and winner != black_player
     @day          = day
     @white_player = white_player
     @black_player = black_player
     @winner       = winner
     @weight       = weight
     @black_player_vpd = nil   # These are set later when added into the database
     @white_player_vpd = nil
  end
  def getWeight(currPlayer)
    oppVpd = self.getOpponentVpd(currPlayer)
    weight = @weight
    if not oppVpd.player.anchor_R and oppVpd.player.num_win + oppVpd.player.num_loss < 10
       weight /= (10.0 - oppVpd.player.num_win - oppVpd.player.num_loss)
    end
    return weight
  end
  def getOpponent(player)
    return player == @white_player ? @black_player : @white_player
  end
  def getOpponentVpd(player)
     return player == @white_player ? @black_player_vpd : @white_player_vpd
  end
  def thisPlayerWon(player)
    return player == @winner
  end
  def tostring()
    if @winner == @white_player
      s = "%s (%0.0f) > %s (%0.0f)" % [
        @white_player.name, @white_player_vpd.r.elo(),
        @black_player.name, @black_player_vpd.r.elo()]
    else
      s = "%s (%0.0f) < %s (%0.0f)" % [
        @white_player.name, @white_player_vpd.r.elo(),
        @black_player.name, @black_player_vpd.r.elo()]
    end
    s += " weight= %0.2f" % (@weight) if @weight != 1.0
    return s
  end
end
            
module WHR

MMITER_CHANGE_LIMIT = 1.0
MMITER_TURN_LIMIT = 3000
LINK_STRENGTH = 2000.0        # draws/days
MIN_LINK_STRENGTH = 20.0    # Prevent weird things happening in weird cases (player doesn't play for a long time)
PRIOR_WEIGHT  = 2.0
START_TIME = DateTime.now()

def self.tostring_now()  return "%fs" % [(DateTime.now() - START_TIME)*24*60*60] end

def self.virtualDrawWeight(p1, p2)
  weight = LINK_STRENGTH / (p1 - p2).abs
  weight = MIN_LINK_STRENGTH if weight < MIN_LINK_STRENGTH
  return weight
end

def self.mmOneVpd(currPlayer, dayidx)
  wins = 0.0
  div  = 0.0
  currPlayerVpd = currPlayer.vpd[dayidx]
  neighborVpdList = []
  neighborVpdList.push(currPlayer.vpd[dayidx-1]) if dayidx > 0
  neighborVpdList.push(currPlayer.vpd[dayidx+1]) if dayidx < currPlayer.vpd.length-1
  for neighborVpd in neighborVpdList
    num_draws = virtualDrawWeight(currPlayerVpd, neighborVpd)
    wins += 0.5 * num_draws
    div  += num_draws / (currPlayerVpd.r.gamma + neighborVpd.r.gamma)
  end
  prior_games = []
  # Apply the prior to the first day only
  prior_games = currPlayer.prior_games if dayidx == 0
  for game in currPlayerVpd.games + prior_games
    oppVpd = game.getOpponentVpd(currPlayer)
    weight = game.getWeight(currPlayer)
    div += weight / (currPlayerVpd.r.gamma + oppVpd.r.gamma)
    wins += weight if game.winner == currPlayer
  end
  return wins/div
end
      
def self.findUpsets()
  for currPlayer in ::PDB.values()
    next if currPlayer.name[0].class == Symbol
    for currPlayerVpd in currPlayer.vpd
      for game in currPlayerVpd.games
        next if game.getOpponentVpd(currPlayer).player.name[0] == Symbol
        if game.winner == currPlayer
          elo_diff = game.getOpponentVpd(currPlayer).r.elo() - currPlayerVpd.r.elo()
          puts "upset: elo_diff=%f %s" % [elo_diff, game.tostring()] if elo_diff > 250
        end
      end
    end
  end
end

def self.mmIterate(turn_limit=MMITER_TURN_LIMIT, players=nil)
  players = ::PDB.values() if players == nil # By default do all players
  for i in (0..turn_limit)
    maxchange = 0
    for currPlayer in players
      if currPlayer.anchor_R != nil
        for currPlayerVpd in currPlayer.vpd
          curr_guess = currPlayer.anchor_R.elo()
          if ( (curr_guess - currPlayerVpd.r.elo).abs > maxchange )
            maxchange = (curr_guess - currPlayerVpd.r.elo).abs
          end
          currPlayerVpd.r = currPlayer.anchor_R.dup()
        end
        next
      end
      for dayidx in (0..currPlayer.vpd.length-1).to_a.reverse
        currPlayerVpd = currPlayer.vpd[dayidx]
        new_rating = Rating.new
        new_rating.gamma = mmOneVpd(currPlayer, dayidx)
        change = new_rating.elo - currPlayerVpd.r.elo
        #puts "name=%s new=%f change=%f" % [currPlayer.name, new_rating.elo, change]
        change = change.abs
        maxchange = change if change > maxchange
        currPlayerVpd.r = new_rating
      end
    end
    if i>1 and i % 10 == 0
      puts "mmIterate int turns=%d maxchange=%f %s" % [i, maxchange, tostring_now()]
    end
    break if maxchange < MMITER_CHANGE_LIMIT
  end
  i>1 and puts "mmIterate int turns=%d maxchange=%f %s" % [i, maxchange, tostring_now()]
end


def self.AddGame(game)
  game.white_player_vpd = game.white_player.addGame(game)
  game.black_player_vpd = game.black_player.addGame(game)
  mmIterate(1, [game.white_player, game.black_player])
end


def self.printPDB()
  for name in sorted(::PDB.keys())
    puts ::PDB[name].tostring(1)
  end
end

def self.printVerbosePDB(verbose=9)
  for name in ::PDB.keys().sort { |a,b| a.to_s <=> b.to_s }
    player = ::PDB[name]
    next if player.name[0].class == Symbol # Skip anchors etc
    puts player.name
    for vpd in ::PDB[name].vpd
      puts "   %6.0f %4d-%02d-%02d numgames=%d winrate=%0.3f" % [vpd.r.elo, vpd.day.year, vpd.day.month, vpd.day.day, vpd.numgames, vpd.winrate]
      next if not verbose > 1
      for game in vpd.games
        opponent = game.getOpponent(player)
        opponentVpd = game.getOpponentVpd(player)
        print "      "
        print game.thisPlayerWon(player) ? "+" : "-"
        print "%6.0f %s" % [opponentVpd.r.elo, opponent.name]
        if game.getWeight(player) != 1.0
          print "weight=%0.2f" % (game.getWeight(player))
        end
        puts
      end
    end
  end
end


def self.sortByMostRecentRating(name)
  return -1.0 * ::PDB[name].mostRecentRating()
end

def self.printSortedPDB()
  new_players = []
  i = 1
  for name in ::PDB.keys().sort {|a,b| PDB[b].mostRecentRating() <=> PDB[a].mostRecentRating}
    num_games = ::PDB[name].num_win + ::PDB[name].num_loss
    s = "%15s %4d %0.0f" % [name, i, ::PDB[name].mostRecentRating()]
    if num_games > 4 and name[0].class != Symbol
      puts s
      i += 1
    else
      new_players.push(s)
    end
  end
  puts
  puts "Players with 4 or less games:"
  for s in new_players do puts s end
end

end  # Module WHR

