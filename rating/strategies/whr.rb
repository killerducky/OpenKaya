require 'date'
require File.expand_path("glicko", File.dirname(__FILE__))
require File.expand_path("../system/", File.dirname(__FILE__))

# WHR requires a lot of state for each player
# Here are some classes to hold that state
# Actual WHR module below

# TODO:
# Dependency on glicko is shady, especially constructing temp Player classes that glicko uses

class WhrError < StandardError; end

# Abstract out what scale the ratings are on
class Rating
  Q = Math.log(10)/400.0    # Convert from classic Elo to natural scale
  KGS_KYU_TRANSFORM = 0.85/Q  # kgs 5k-
  KGS_DAN_TRANSFORM = 1.30/Q  # kgs 2d+
  KD_FIVE_KYU = -4.0         # Strongest 5k on the kyudan scale
  KD_TWO_DAN  =  1.0         # Weakest   2d on the kyudan scale
  A = (KGS_DAN_TRANSFORM - KGS_KYU_TRANSFORM) / (KD_TWO_DAN - KD_FIVE_KYU) # ~ 17.4    Intermediate constant for conversions
  B = KGS_KYU_TRANSFORM - KD_FIVE_KYU*A                                    # ~ 208.6   Intermediate constant for conversions
  FIVE_KYU = (A/2.0)*((KD_FIVE_KYU)**2) + (B*KD_FIVE_KYU)    # ~ 695.2 -- Glicko rating of the strongest 5k
  TWO_DAN  = (A/2.0)*((KD_TWO_DAN )**2) + (B*KD_TWO_DAN )    # ~ 217.3 -- Glicko rating of the weakest 2d
  attr_accessor :elo
  def self.new_aga_rating(aga_rating)
    r = Rating.new()
    r.aga_rating = aga_rating
    return r
  end
  def self.new_kyudan(kyudan)
    r = Rating.new()
    r.kyudan = kyudan
    return r
  end
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
  def kyudan()
    return KD_FIVE_KYU + (@elo-FIVE_KYU)/KGS_KYU_TRANSFORM if @elo < FIVE_KYU
    return KD_TWO_DAN  + (@elo- TWO_DAN)/KGS_DAN_TRANSFORM if @elo >  TWO_DAN
    return (Math.sqrt(2.0*A*@elo+B**2.0)-B)/A
  end
  def aga_rating()
    r = kyudan()
    return r < 0.0 ? r - 1.0 : r + 1.0  # Add the (-1.0,1.0) gap
  end
  def kyudan=(kyudan)
    if kyudan < KD_FIVE_KYU
      @elo = (kyudan - KD_FIVE_KYU)*KGS_KYU_TRANSFORM + FIVE_KYU
    elsif kyudan > KD_TWO_DAN
      @elo = (kyudan - KD_TWO_DAN )*KGS_DAN_TRANSFORM + TWO_DAN
    else
      @elo = ((A*kyudan+B)**2.0 - B**2.0)/(2.0*A)
    end
    return self
  end
  def aga_rating=(aga_rating)
    raise WhrError, "Illegal aga_rating #{aga_rating}" unless aga_rating.abs >= 1.0  # Ratings in (-1.0,1.0) are illegal
    self.kyudan = aga_rating < 0.0 ? aga_rating + 1.0 : aga_rating - 1.0   # Close the (-1.0,1.0) gap
    return self
  end
end

class Rating_delta
  def initialize(r1, r2)
    @r1 = r1
    @r2 = r2
  end
  def gamma()  return 10**((@r1.elo - @r2.elo)/400.0) end
  def elo()    return @r1.elo    - @r2.elo end
  def kyudan() return @r1.kyudan - @r2.kyudan end
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
  def rating() return @r.elo end
  def num_games()
    return @games.length
  end
  def winrate()
    return -1.0 if @games.length == 0
    return @wins / @games.length
  end
end


class WHR_Player
  attr_accessor :vpd, :name, :prior_initialized, :num_win, :num_games, :anchor_R, :prior_games
  def initialize(name, anchor_R=nil)
    @vpd = []       # List of PlayerDay objects, must be in chronological order
    @name = name
    @prior_initialized = false
    @num_win = 0
    @num_games = 0
    if anchor_R != nil
      @anchor_R = anchor_R.dup()   # Anchor player's rating
    else
      @anchor_R = nil
    end
    @prior_games = []  # Virtual games on the first player day to avoid all wins / all losses spiraling
  end
  def get_vpd(day)
    for vpd in @vpd
      return vpd if vpd.day == day
    end
    raise "Day %d not found in player %s" % day, @name
  end
  def add_new_vpd(day)
    if (@vpd != [])
      raise "Days assumed to be chronological" unless @vpd[-1].day < day
    end
    @vpd.push(PlayerDay.new(day, self))
    @vpd[-1].r = @anchor_R.dup() if @anchor_R
  end
  def add_prior(day)
    # Add two virtual games against the :prior_anchor on the first day
    @prior_games = [Game.new(day, self, ::PDB[:prior_anchor], "aga", 0, 7.5, self                , WHR::PRIOR_WEIGHT),
                    Game.new(day, self, ::PDB[:prior_anchor], "aga", 0, 7.5, ::PDB[:prior_anchor], WHR::PRIOR_WEIGHT)]
    for game in @prior_games
      # Use the first vpd for each player
      # It's a bit strange to use only first vpd for the :prior_anchor, 
      #   but it doesn't matter and it's easier
      if ::PDB[:prior_anchor].vpd == []
         ::PDB[:prior_anchor].add_new_vpd(day)
      end
      game.white_player_vpd = @vpd[0]
      game.black_player_vpd = ::PDB[:prior_anchor].vpd[0]
    end
  end
  def add_game(game)
    if @vpd == [] or @vpd[-1].day != game.day
      if @name[0].class != Symbol or @anchor_R or @vpd == []  # Only use one vpd for special Symbol players
        self.add_new_vpd(game.day)
      end
    end
    if not @prior_initialized
      self.add_prior(game.day)
      @prior_initialized = true
    end
    @vpd[-1].games.push(game)
    if game.winner == self
      @vpd[-1].wins += 1.0
      @num_win += 1
    end
    @num_games += 1
    return @vpd[-1]  # return link to the vpd used
  end
  def tostring(verbose=0)
    s = @name
    for vpd in @vpd
      s += "\n" if verbose > 0
      s += vpd.r.tostring()
      if verbose >= 1
        s += " day=%s num_games=%d winrate=%0.3f" % [vpd.day, vpd.num_games(), vpd.winrate()]
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
  def rating()
    return Rating.new(-1.0) if @vpd == []
    return @vpd[-1].r
  end
  def r() return rating() end
end


class Game
  EVEN_KOMI = { "aga" => 7, "jpn" => 6 }    # even komi, after doing floor()
  attr_accessor :day, :white_player, :black_player, :winner, :weight, :black_player_vpd, :white_player_vpd
  attr_accessor :rules, :handi, :komi
  def self.new_even(day, white_player, black_player, winner, weight=1.0)
     return Game.new(day, white_player, black_player, "aga", 0, 7.5, winner, weight)
  end
  def initialize(day, white_player, black_player, rules, handi, komi, winner, weight=1.0)
     raise "Invalid winner" if winner != white_player and winner != black_player
     @day          = day
     @white_player = white_player
     @black_player = black_player
     @rules        = rules
     @handi        = handi
     @komi         = komi.floor
     @winner       = winner
     @weight       = weight
     @black_player_vpd = nil   # These are set later when added into the database
     @white_player_vpd = nil
     raise WhrError, "Handi=1 is illegal" if @handi == 1
  end
  def get_weight(curr_player)
    opp_vpd = self.get_opponent_vpd(curr_player)
    weight = @weight
    if not opp_vpd.player.anchor_R and opp_vpd.player.num_games < 10
      # Less weight if the opponent has not played many games yet
      weight /= (10.0 - opp_vpd.player.num_games)
    end
    return weight
  end
  def get_opponent(player)
    return player == @white_player ? @black_player : @white_player
  end
  def get_opponent_vpd(player)
     return player == @white_player ? @black_player_vpd : @white_player_vpd
  end
  def this_player_won(player)
    return player == @winner
  end
  def handi_komi_advantage(player)
    even_komi = EVEN_KOMI[@rules]
    handi = @handi
    handi -= 1 if @handi > 0
    hka = handi + (even_komi-@komi)/(even_komi*2.0)
    avg_kyudan = (@white_player_vpd.r.kyudan + @black_player_vpd.r.kyudan) / 2.0
    r1 = Rating.new_kyudan(avg_kyudan + hka*0.5)
    r2 = Rating.new_kyudan(avg_kyudan - hka*0.5)
    rating_delta = player == @white_player ? Rating_delta.new(r1, r2) : Rating_delta.new(r2, r1)
    #puts "hka handi=%f komi=%f hka=%f avg=%f r1=%f r2=%f" % [handi, @komi, hka, avg_kyudan, r1.kyudan, r2.kyudan]
    return rating_delta
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

PRIOR_WEIGHT  = 2.0
MMITER_CHANGE_LIMIT = 1.0
LINK_STRENGTH = 2000.0        # draws/days
MIN_LINK_STRENGTH = 20.0      # Prevent weird things happening in weird cases (player doesn't play for a long time)
MMITER_TURN_LIMIT = 3000
START_TIME = DateTime.now()   # For performance tracking only

def self.tostring_now()  return "%fs" % [(DateTime.now() - START_TIME)*24*60*60] end

def self.virtual_draw_weight(day1, day2)
  weight = LINK_STRENGTH / (day1 - day2).abs
  weight = MIN_LINK_STRENGTH if weight < MIN_LINK_STRENGTH
  return weight
end

def self.mm_one_vpd(curr_player, dayidx)
  wins = 0.0
  div  = 0.0
  curr_player_vpd = curr_player.vpd[dayidx]
  neighbor_vpd_list = []
  neighbor_vpd_list.push(curr_player.vpd[dayidx-1]) if dayidx > 0
  neighbor_vpd_list.push(curr_player.vpd[dayidx+1]) if dayidx < curr_player.vpd.length-1
  for neighbor_vpd in neighbor_vpd_list
    num_draws = virtual_draw_weight(curr_player_vpd.day, neighbor_vpd.day)
    wins += 0.5 * num_draws
    div  += num_draws / (curr_player_vpd.r.gamma + neighbor_vpd.r.gamma)
  end
  prior_games = []
  # Apply the prior to the first day only
  prior_games = curr_player.prior_games if dayidx == 0
  for game in curr_player_vpd.games + prior_games
    opp_vpd = game.get_opponent_vpd(curr_player)
    weight = game.get_weight(curr_player)
    hka = game.handi_komi_advantage(curr_player)
    #puts "hka=%f %f" % [hka.gamma, hka.kyudan]
    div += weight / (curr_player_vpd.r.gamma + opp_vpd.r.gamma*hka.gamma)
    wins += weight if game.winner == curr_player
  end
  return wins/div
end
      
def self.find_upsets()
  for curr_player in ::PDB.values()
    next if curr_player.name[0].class == Symbol
    for curr_player_vpd in curr_player.vpd
      for game in curr_player_vpd.games
        next if game.get_opponent_vpd(curr_player).player.name[0] == Symbol
        if game.winner == curr_player
          elo_diff = game.get_opponent_vpd(curr_player).r.elo() - curr_player_vpd.r.elo()
          puts "upset: elo_diff=%f %s" % [elo_diff, game.tostring()] if elo_diff > 250
        end
      end
    end
  end
end

def self.mm_iterate(turn_limit=MMITER_TURN_LIMIT, players=nil)
  players = ::PDB.values() if players == nil # By default do all players
  for i in (0..turn_limit)
    maxchange = 0
    for curr_player in players
      if curr_player.anchor_R != nil
        for curr_player_vpd in curr_player.vpd
          curr_guess = curr_player.anchor_R.elo()
          if ( (curr_guess - curr_player_vpd.r.elo).abs > maxchange )
            maxchange = (curr_guess - curr_player_vpd.r.elo).abs
          end
          curr_player_vpd.r = curr_player.anchor_R.dup()
        end
        next
      end
      for dayidx in (0..curr_player.vpd.length-1).to_a.reverse
        curr_player_vpd = curr_player.vpd[dayidx]
        new_rating = Rating.new
        new_rating.gamma = mm_one_vpd(curr_player, dayidx)
        change = new_rating.elo - curr_player_vpd.r.elo
        #puts "name=%s new=%f change=%f" % [curr_player.name, new_rating.elo, change]
        change = change.abs
        maxchange = change if change > maxchange
        curr_player_vpd.r = new_rating
      end
    end
    if i>1 and i % 10 == 0
      puts "mm_iterate int turns=%d maxchange=%f %s" % [i, maxchange, tostring_now()]
    end
    break if maxchange < MMITER_CHANGE_LIMIT
  end
  i>5 and puts "mm_iterate int turns=%d maxchange=%f %s" % [i, maxchange, tostring_now()]
end


def self.add_game(game)
  game.white_player_vpd = game.white_player.add_game(game)
  game.black_player_vpd = game.black_player.add_game(game)
  mm_iterate(1, [game.white_player, game.black_player])
end


def self.print_PDB()
  puts "print_PDB"
  for name in sorted(::PDB.keys())
    puts ::PDB[name].tostring(1)
  end
end

def self.print_verbose_PDB(verbose=9)
  puts "print_verbose_PDB"
  for name in ::PDB.keys().sort { |a,b| a.to_s <=> b.to_s }
    player = ::PDB[name]
    next if player.name[0].class == Symbol # Skip anchors etc
    puts player.name
    for vpd in ::PDB[name].vpd
      puts "   %6.0f %4d-%02d-%02d num_games=%d winrate=%0.3f" % [vpd.r.elo, vpd.day.year, vpd.day.month, vpd.day.day, vpd.num_games, vpd.winrate]
      next if not verbose > 1
      for game in vpd.games
        opponent = game.get_opponent(player)
        opponent_vpd = game.get_opponent_vpd(player)
        print "      "
        print game.this_player_won(player) ? "+" : "-"
        print "%6.0f %s" % [opponent_vpd.r.elo, opponent.name]
        if game.get_weight(player) != 1.0
          print " weight=%0.2f" % (game.get_weight(player))
        end
        puts
      end
    end
  end
  puts
end


def self.print_sorted_PDB()
  puts "print_sorted_PDB"
  new_players = []
  i = 1
  # TODO implement <=> for rating class
  for name in ::PDB.keys().sort {|a,b| PDB[b].rating.elo <=> PDB[a].rating.elo}  
    player = ::PDB[name]
    num_games = player.num_games
    s = "%15s #%3d %6.0f %6.2f num_games=%d" % [name, i, player.rating.elo, player.rating.aga_rating, num_games]
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
  puts
end

def self.print_constants()
  puts "PRIOR_WEIGHT        = %f" % PRIOR_WEIGHT        
  puts "MMITER_CHANGE_LIMIT = %f" % MMITER_CHANGE_LIMIT 
  puts "LINK_STRENGTH       = %d" % LINK_STRENGTH       
  puts "MIN_LINK_STRENGTH   = %f" % MIN_LINK_STRENGTH   
  puts "MMITER_TURN_LIMIT   = %d" % MMITER_TURN_LIMIT   
end

end  # Module WHR

