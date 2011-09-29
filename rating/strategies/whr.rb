require 'date'
require File.expand_path("glicko", File.dirname(__FILE__))
require File.expand_path("../system/", File.dirname(__FILE__))

#module WHR

MMITER_CHANGE_LIMIT = 0.01
MMITER_TURN_LIMIT = 3000
LINK_STRENGTH = 2000.0        # draws/days
MIN_LINK_STRENGTH = 20.0    # Prevent weird things happening in weird cases (player doesn't play for a long time)
PRIOR_WEIGHT  = 2.0
DAYONE = DateTime.parse("2000-01-01")
START_TIME = DateTime.now()
PDB = {}

#class RType: (elo, shifted_elo, kgsdan, kgskyu, egf, gamma) = range(6)

def gammaToElo(gamma)    return 400.0*Math::log10(gamma) end
def eloToGamma(elo)      return 10**(elo/400.0) end
def pWinEloDiff(elo_diff) return 1/(1+10**(elo_diff/400.0)) end
#def pWinGamma(gamma):  return gamma / (gamma + 1.0)          # !! Not verified
#def eloDiffGivenPWin(pW): return math.log((1-pW)/pW) * 400   # !! Not verified
def tostring_now()  return "%fs" % [(DateTime.now() - START_TIME)*24*60*60] end

class Rating
  attr_accessor :elo
  def initialize(elo)
    @elo = elo
  end
  def gamma=(gamma)
    @elo = gammaToElo(gamma)
  end
  def gamma()
    return eloToGamma(@elo)
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
    return len(@games)
  end
  def winrate()
    return -1.0 if len(@games) == 0
    return @wins / len(@games)
  end
end

class WHR_Player
  attr_accessor :vpd, :name, :prior_initialized, :group, :num_win, :num_loss, :anchor_R, :prior_games
  def initialize(name, anchor_R=nil)
    @vpd = []       # List of PlayerDay objects, must be in chronological order
    @name = name
    @prior_initialized = false
    @group = nil
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
    @prior_games = [Game.new(day, self, PDB["_PRIOR_ANCHOR"], self                , PRIOR_WEIGHT),
                    Game.new(day, self, PDB["_PRIOR_ANCHOR"], PDB["_PRIOR_ANCHOR"], PRIOR_WEIGHT)]
    for game in @prior_games
      # Use the first vpd for each player
      # It's a bit strange to use only first vpd for the _PRIOR_ANCHOR, 
      #   but it doesn't matter and it's easier
      if PDB["_PRIOR_ANCHOR"].vpd == []
         PDB["_PRIOR_ANCHOR"].addNewVpd(day)
      end
      game.white_player_vpd = @vpd[0]
      game.black_player_vpd = PDB["_PRIOR_ANCHOR"].vpd[0]
    end
  end
  def addGame(game)
    if @vpd == [] or @vpd[-1].day != game.day
      if @name[0] != "_" or @vpd == []  # Only use one vpd for "_xxx" players
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
  def tostring(rtype, verbose=0)
    s = @name
    for vpd in @vpd
      s += "\n" if verbose > 0
      s += vpd.r.tostring(rtype)
      if verbose >= 1
        s += " day=%s numgames=%d winrate=%0.3f" % [vpd.daytostr(), vpd.numgames(), vpd.winrate()]
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
            
def virtualDrawWeight(p1, p2)
  weight = LINK_STRENGTH / (p1 - p2).abs
  weight = MIN_LINK_STRENGTH if weight < MIN_LINK_STRENGTH
  return weight
end

def mmOneVpd(currPlayer, dayidx)
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
      
def findUpsets()
  for currPlayer in PDB.values()
    next if currPlayer.name[0] == "_"
    for currPlayerVpd in currPlayer.vpd
      for game in currPlayerVpd.games
        next if game.getOpponentVpd(currPlayer).player.name[0] == "_"
        if game.winner == currPlayer
          elo_diff = game.getOpponentVpd(currPlayer).r.elo() - currPlayerVpd.r.elo()
          puts "upset: elo_diff=%f %s" % [elo_diff, game.tostring()] if elo_diff > 250
        end
      end
    end
  end
end

def mmIterate(turn_limit=MMITER_TURN_LIMIT, players=nil)
  players = PDB.values() if players == nil # By default do all players
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
        newGamma = mmOneVpd(currPlayer, dayidx)
        change = gammaToElo(newGamma) - currPlayerVpd.r.elo()
        puts "name=%s new=%f change=%f" % [currPlayer.name, gammaToElo(newGamma), change]
        change = change.abs
        maxchange = change if change > maxchange
        currPlayerVpd.r.gamma = newGamma
        #print currPlayer.tostring(RType.elo, 1)
        #sys.stdout.flush()
      end
    end
    if i>0 and i % 10 == 0
      puts "mmIterate int turns=%d maxchange=%f %s" % [i, maxchange, tostring_now()]
    end
    break if maxchange < MMITER_CHANGE_LIMIT
  end
  i>0 and puts "mmIterate int turns=%d maxchange=%f %s" % [i, maxchange, tostring_now()]
end


def AddGame(game)
  game.white_player_vpd = game.white_player.addGame(game)
  game.black_player_vpd = game.black_player.addGame(game)
  mmIterate(1, [game.white_player, game.black_player])
end


def printPDB(rtype)
  for name in sorted(PDB.keys())
    puts PDB[name].tostring(rtype, 1)
  end
  #sys.stdout.flush()
end

def printVerbosePDB(rtype, verbose=9)
  for name in sorted(PDB.keys())
    player = PDB[name]
    next if player.name[0] == "_" # Skip anchors etc
    puts player.name
    for vpd in PDB[name].vpd
      puts "   %s day=%s numgames=%d winrate=%0.3f" % [vpd.r.tostring(rtype), vpd.daytostr(), vpd.numgames(), vpd.winrate()]
      next if not verbose > 1
      for game in vpd.games
        opponent = game.getOpponent(player)
        opponentVpd = game.getOpponentVpd(player)
        print "      "
        print game.thisPlayerWon(player) ? "+" : "-"
        print opponentVpd.r.tostring(rtype), opponent.name
        if game.getWeight(player) != 1.0
          print "weight=%0.2f" % (game.getWeight(player))
        end
        puts
      end
    end
  end
end


def sortByMostRecentRating(name)
  return -1.0 * PDB[name].mostRecentRating()
end

def printSortedPDB(rtype)
  new_players = []
  i = 1
  for name in PDB.keys().sort {|a,b| b.mostRecentRating() <=> a.mostRecentRating}
    num_games = PDB[name].num_win + PDB[name].num_loss
    #if num_games < 10
    #   print "%15s %4d %0.0f %s numgames=%d" % (name, i, PDB[name].mostRecentRating(), PDB[name].group, num_games)
    #else
    s = "%15s %4d %0.0f %s" % [name, i, PDB[name].mostRecentRating(), PDB[name].group]
    if num_games > 4 and name[0] != "_"
      puts s
      i += 1
    else
      new_players.push(s)
    end
  end
  puts
  puts "Players with 4 or less games:"
  for s in new_players do puts s end
  #sys.stdout.flush()
end

#end  # Module WHR

