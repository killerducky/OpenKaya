require "date"
require "gsl"
#include GSL::MultiMin
require File.expand_path("../system/", File.dirname(__FILE__))

# WHR requires a lot of state for each player
# Here are some classes to hold that state
# Actual WHR module below

#
# TODO:
# - Add ability to set an initial rank for a player
#   Currently set to the rating of the first opponent
#   Still pretty degenerate when first opponent is also unrated!
#   (Will default to elo=0 aka 1k/1d boundary)
#   (You can already sorta do this by maunally setting a different prior.)
#

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
  FIVE_KYU = (A/2.0)*((KD_FIVE_KYU)**2) + (B*KD_FIVE_KYU)    # ~ 695.2 -- Elo rating of the strongest 5k
  TWO_DAN  = (A/2.0)*((KD_TWO_DAN )**2) + (B*KD_TWO_DAN )    # ~ 217.3 -- Elo rating of the weakest 2d
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
  def self.advantage_in_stones(handi, komi, even_komi)
    raise WhrError, "Handi=1 is illegal" if handi == 1
    komi = komi.floor
    even_komi = even_komi.floor
    handi -= 1 if handi > 0
    return handi + (even_komi-komi)/(even_komi*2.0)
  end
  def initialize(elo=0)
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
# initial_r_guess is just an optimization to help the algorithm converge faster
class PlayerDay
  attr_accessor :day, :games, :r, :wins, :player
  def initialize(day, player, initial_r_guess)
    @day = day
    @games    = []       # list of games
    @r        = initial_r_guess ? initial_r_guess : Rating.new(0.0)
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
    @num_win = 0
    @num_games = 0
    if anchor_R != nil
      @anchor_R = anchor_R.dup()   # Anchor player's rating
      @prior_initialized = true    # Don't need a prior on anchors
    else
      @anchor_R = nil
      @prior_initialized = false
    end
    @prior_games = []  # Virtual games on the first player day to avoid all wins / all losses spiraling
  end
  def get_vpd(day)
    for vpd in @vpd
      return vpd if vpd.day == day
    end
    raise "Day %d not found in player %s" % day, @name
  end
  def add_new_vpd(day, initial_r_guess)
    if (@vpd != [])
      raise "Days assumed to be chronological" unless @vpd[-1].day < day
    end
    @vpd.push(PlayerDay.new(day, self, initial_r_guess))
    @vpd[-1].r = anchor_R() if @anchor_R
    # Important: Code relies on using the same anchor_R again, so you can change just that one.
    # Also right now anchors only have one VPD anyways.
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
         ::PDB[:prior_anchor].add_new_vpd(day, ::PDB[:prior_anchor].anchor_R.dup)
      end
      game.white_player_vpd = @vpd[0]
      game.black_player_vpd = ::PDB[:prior_anchor].vpd[0]
    end
  end
  def add_game(game)
    if @vpd == [] or @vpd[-1].day != game.day
      if ((@name.class != Symbol) and (@anchor_R == nil) or @vpd == [])
	# Initial Guess same rating as previous vpd if it exists,
	# Otherwise initial guess is opponent's rating
	initial_r_guess = @vpd != [] ? @vpd[-1].r.dup : game.get_opponent(self).rating.dup
	self.add_new_vpd(game.day, initial_r_guess)
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
    s = @name.to_s
    s += verbose > 0 ? "\n" : " "
    for vpd in @vpd
      s += "%0.0f" % [vpd.r.elo]
      if verbose >= 1
        s += " day=%04d-%02d-%02d num_games=%d winrate=%0.3f" % [vpd.day.year, vpd.day.month, vpd.day.day, vpd.num_games(), vpd.winrate()]
        if verbose >= 2
          for game in vpd.games
            if game.winner == self then s += " W"
            else                        s += " L" end
          end
        end
      end
      s += verbose > 0 ? "\n" : " "
    end
    return s
  end
  def rating()
    return Rating.new(-1.0) if @vpd == []   # !! TODO should probably return nil
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
    hka = Rating.advantage_in_stones(@handi, @komi, EVEN_KOMI[@rules])
    avg_kyudan = (@white_player_vpd.r.kyudan + @black_player_vpd.r.kyudan) / 2.0
    r1 = Rating.new_kyudan(avg_kyudan + hka*0.5)
    r2 = Rating.new_kyudan(avg_kyudan - hka*0.5)
    rating_delta = player == @white_player ? Rating_delta.new(r1, r2) : Rating_delta.new(r2, r1)
    #puts "hka handi=%f komi=%f hka=%f avg=%f r1=%f r2=%f" % [handi, @komi, hka, avg_kyudan, r1.kyudan, r2.kyudan]
    return rating_delta
  end

  def tostring()
    if @winner == @white_player
      s = "w=%s (%0.0f) > b=%s (%0.0f)" % [
        @white_player.name, @white_player_vpd.r.elo(),
        @black_player.name, @black_player_vpd.r.elo()]
    else
      s = "w=%s (%0.0f) < b=%s (%0.0f)" % [
        @white_player.name, @white_player_vpd.r.elo(),
        @black_player.name, @black_player_vpd.r.elo()]
    end
    s += " weight= %0.2f" % (@weight) if @weight != 1.0
    return s
  end
end

class Tmp_hessian_vars
  attr_accessor :b, :d, :h, :G, :dprime, :GV, :x
  def initialize()
    @b = 0.0
    @d = 0.0
    @h = 0.0
    @G = 0.0
    @dprime = 0.0
    @GV = 0.0
    @x = 0.0
  end
end

module WHR

PRIOR_WEIGHT  = 2.0
MMITER_CHANGE_LIMIT = 0.1
NMSIMPLEX_SIZE      = 0.1
MAX_LINK_STRENGTH = 200.0     # draws/days
MIN_LINK_STRENGTH = 4.0       # Prevent weird things happening in weird cases (player doesn't play for a long time)
LINK_STRENGTH_SCALE = MAX_LINK_STRENGTH*7.0  # First 7 days don't actually reduce max link strength
MMITER_TURN_LIMIT = 3000      # Quit if we do many loops without hitting MMITER_CHANGE_LIMIT
HESSIAN_EPSILON = 0.0         # TODO make sure zero is ok, original was 0.1
START_TIME = DateTime.now()   # For performance tracking only
DEBUG = false

def self.tostring_now()  return "%fs" % [(DateTime.now() - START_TIME)*24*60*60] end

def self.virtual_draw_weight(day1, day2)
  weight = LINK_STRENGTH_SCALE / (day1 - day2).abs
  weight = [weight, MAX_LINK_STRENGTH].min
  weight = [MIN_LINK_STRENGTH, weight].max
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
    opp_adjusted_r = Rating.new(opp_vpd.r.elo+hka.elo)
    div += weight / (curr_player_vpd.r.gamma + opp_adjusted_r.gamma)
    wins += weight if game.winner == curr_player
  end
  return wins/div
end

def self.find_upsets()
  for curr_player in ::PDB.values()
    next if curr_player.name.class == Symbol
    for curr_player_vpd in curr_player.vpd
      for game in curr_player_vpd.games
        next if game.get_opponent_vpd(curr_player).player.name == Symbol
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
  for i in (1..turn_limit)
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
    if i>1 and i % 100 == 0
      #puts "mm_iterate int turns=%d maxchange=%f %s" % [i, maxchange, tostring_now()]
    end
    break if maxchange < MMITER_CHANGE_LIMIT
  end
  i and i>100 and puts "mm_iterate int turns=%d maxchange=%f %s" % [i, maxchange, tostring_now()]
end


# Compute Variance
def self.compute_variance(player)
  return if player.vpd.length == 0 # skip players with no games
  tmp_vars = Array.new(player.vpd.length, Tmp_hessian_vars.new())

  #
  # Compute Hessian
  #

  # loop over playerdays of this player
  for i in (0..player.vpd.length-1)
    vpd = player.vpd[i]
    h = 0.0
    g = 0.0
    prior_games = []
    prior_games = player.prior_games if i == 0
    for game in vpd.games + prior_games
      opp_vpd = game.get_opponent_vpd(player)
      weight = game.get_weight(player)
      hka = game.handi_komi_advantage(player)
      opp_adjusted_r = Rating.new(opp_vpd.r.elo+hka.elo)
      inv = weight / (vpd.r.gamma + opp_adjusted_r.gamma)
      g += inv
      h += opp_adjusted_r.gamma * inv * inv   # opponent_gamma / ( my_gamma + opponent_gamma)^2
    end
    # store h and g
    tmp_vars[i].d -= h * vpd.r.gamma + HESSIAN_EPSILON
    tmp_vars[i].h -= h * vpd.r.gamma + HESSIAN_EPSILON
    tmp_vars[i].G += vpd.wins - vpd.r.gamma * g
    # link to next playerday
    if i < player.vpd.length-1
      next_vpd = player.vpd[i+1]
      virtual_wins = virtual_draw_weight(vpd.day, next_vpd.day)
      b = virtual_wins * 0.5
      g = ((next_vpd.r.gamma - vpd.r.gamma) / vpd.r.gamma) * virtual_wins * 0.5
      tmp_vars[i].b = b
      tmp_vars[i].d -= b
      tmp_vars[i].h -= b
      tmp_vars[i].G += g

      a = b / tmp_vars[i].d
      tmp_vars[i+1].d = -b - a * b
      tmp_vars[i+1].h = -b
      tmp_vars[i+1].G = -g - a * tmp_vars[i].G
    end
  end

  #
  # Compute Variance
  #
  vpd = player.vpd
  i = vpd.length-1
  tmp_vars[i].dprime = tmp_vars[i].h    # UL-decomposition
  tmp_vars[i].GV = -1 / tmp_vars[i].d

  # Don't really need the rest because I really only want to know GV of the player at the end for now
  i -= 1
  while (i >= 0)
    tmp_vars[i].dprime = tmp_vars[i].h - tmp_vars[i].b * tmp_vars[i].b / tmp_vars[i+1].dprime
    tmp_vars[i].GV = tmp_vars[i+1].dprime / (tmp_vars[i].b * tmp_vars[i].b - tmp_vars[i].d * tmp_vars[i+1].dprime)
    i -= 1
  end
  #return tmp_vars[-1].GV / Rating::Q  # Return in Elo -- the calculation gives natural scale instead
  return tmp_vars
end

# Apply Newton's method to update all the player-days of one player
def self.newton(player)
  return if player.vpd.length == 0   # skip players with no games
  return if player.anchor_R        # skip anchors
  debug = true
  tmp_vars = compute_variance(player)
  i = player.vpd.length-1
  vpd = player.vpd[i]
 #vpd.G         /= vpd.d
  tmp_vars[i].x = tmp_vars[i].G /  tmp_vars[i].d
  puts "Before Newton day=%04d-%02d-%02d" % [vpd.day.year, vpd.day.month, vpd.day.day]
  puts "vpd.gamma=%f x=%f" % [vpd.r.gamma, tmp_vars[i].x]
  puts player.tostring(1)
  vpd.r.gamma *= Math.exp(-tmp_vars[i].x)
  i -= 1
  while (i >= 0)
    vpd = player.vpd[i]
    next_vpd = player.vpd[i+1]
   #tmp_vars[i].G = (tmp_vars[i].G - tmp_vars[i].b * tmp_vars[i].G) / tmp_vars[i].d
    tmp_vars[i].x = (tmp_vars[i].G - tmp_vars[i].b * tmp_vars[i].x) / tmp_vars[i].d
    puts "Before Newton day=%04d-%02d-%02d" % [vpd.day.year, vpd.day.month, vpd.day.day]
    player.tostring(1)
    vpd.r.gamma *= Math.exp(-tmp_vars[i].x)
    i -= 1
  end
end

def self.nmsimplex(verbose=0)
  puts "begin nmsimplex " + tostring_now() if verbose>0

  # Create a linear mapping of vpd objects
  vpd_map = []
  for name in ::PDB.keys()
    player = ::PDB[name]
    next if player.name[0].class == Symbol
    next if player.anchor_R
    for dayidx in (0..PDB[name].vpd.length-1)
      vpd = PDB[name].vpd[dayidx]
      vpd_map.push(vpd)
    end
  end
  num_vpd = vpd_map.length

  my_f = Proc.new { |x|
    for i in (0..num_vpd-1)
      vpd_map[i].r.elo = x[i]  # Map new ratings from the algorithm
      #print "v[%d]=%0.2f " % [i, v[i]]
    end
    #get_log_likelyhood()
    get_direct_log_likelyhood()
  }
  
  #my_df = Proc.new { |x|
  #  for i in (0..num_vpd-1)
  #    vpd_map[i].r.elo = x[i]  # Map new ratings from the algorithm
  #    #print "v[%d]=%0.2f " % [i, v[i]]
  #  end
  #  get_direct_log_likelyhood_df()
  #}
    
  my_func = GSL::MultiMin::Function.alloc(my_f, num_vpd)
  x = GSL::Vector.alloc(num_vpd)
  for i in (0..num_vpd-1)
    x[i] = vpd_map[i].r.elo
  end
  ss = GSL::Vector.alloc(num_vpd)
  ss.set_all(2.0)
  minimizer = GSL::MultiMin::FMinimizer.alloc(GSL::MultiMin::FMinimizer::NMSIMPLEX2RAND, num_vpd)

  minimizer.set(my_func, x, ss)

  iter = 0
  begin
    iter += 1
    status = minimizer.iterate()
    status = minimizer.test_size(NMSIMPLEX_SIZE)
    if verbose>1
      x = minimizer.x
      printf("%5d ", iter)
      for i in 0...num_vpd do
        printf("%10.2f ", x[i])
      end
    end
    printf(" f() = %7.3f size = %.3f\n", minimizer.fval, minimizer.size) if verbose>1
  end while status == GSL::CONTINUE and iter < 5000
  raise "Error" if iter == 5000
  if status == GSL::SUCCESS
    puts("converged to minimum at") if verbose>0
  end
  printf(" f() = %7.3f size = %.3f\n", minimizer.fval, minimizer.size) if verbose>0

  x = minimizer.x
  for i in (0..num_vpd-1)
    vpd_map[i].r.elo = x[i]  # Map new ratings from the algorithm
    #print "v[%d]=%0.2f " % [i, v[i]]
  end
  puts "end nmsimplex " + tostring_now() if verbose > 0

end


def self.calc_ratings_fdf(verbose=0)
  puts "begin calc_ratings_fdf " + tostring_now() if verbose>0

  # Create a linear mapping of vpd objects
  vpd_map = []
  for name in ::PDB.keys().sort { |a,b| a.to_s <=> b.to_s }
    player = ::PDB[name]
    next if player.name[0].class == Symbol
    next if player.anchor_R
    for dayidx in (0..PDB[name].vpd.length-1)
      vpd = PDB[name].vpd[dayidx]
      vpd_map.push(vpd)
    end
  end
  num_vpd = vpd_map.length

  my_f = Proc.new { |x|
    for i in (0..num_vpd-1)
      vpd_map[i].r.elo = x[i]  # Map new ratings from the algorithm
      print "my_f x[%d]=%0.3f " % [i, x[i]] if verbose>1
    end
    ll = get_log_likelyhood()
    #ll = get_direct_log_likelyhood()
    puts "ll=%0.3f" % [ll] if verbose>1
    ll
  }
  
  my_df = Proc.new { |x, params, df|
    for i in (0..num_vpd-1)
      vpd_map[i].r.elo = x[i]  # Map new ratings from the algorithm
      #print "v[%d]=%0.2f " % [i, v[i]]
    end
    get_log_likelyhood_df(df)
    #get_direct_log_likelyhood_df(df)
    if verbose>1
      for i in (0..num_vpd-1)
        puts "my_df name=%3s x[%d]=%0.3f params=%0.3f df=%0.5f" % [vpd_map[i].player.name, i, x[i], params[i], df[i]]
      end
    end
  }
    
  my_func = GSL::MultiMin::Function_fdf.alloc(my_f, my_df, num_vpd)
  my_func.set_params([1.0, 2.0])      # parameters

  x = GSL::Vector.alloc(num_vpd)
  for i in (0..num_vpd-1)
    x[i] = vpd_map[i].r.elo
  end
  # For some reason BFGS2 does not work on my testcase
  #minimizer = GSL::MultiMin::FdfMinimizer.alloc(GSL::MultiMin::FdfMinimizer::VECTOR_BFGS2, num_vpd)
  minimizer = GSL::MultiMin::FdfMinimizer.alloc(GSL::MultiMin::FdfMinimizer::VECTOR_BFGS, num_vpd)

  minimizer.set(my_func, x, 10.0, 0.1)   # 3rd arg is stepsize, 4th arg is "tol"

  iter = 0
  begin
    iter += 1
    status = minimizer.iterate()
    status = minimizer.test_gradient(1e-3)
    x = minimizer.x
    if verbose>0
      printf("iter=%5d ", iter)
      for i in 0...num_vpd do
        printf("%10.2f ", x[i])
      end
    end
    printf(" f() = %7.3f size = ????\n", minimizer.f) if verbose>0
  #end while status == GSL::CONTINUE and iter < 500
  end while status == GSL::CONTINUE and iter < 50
  raise "iter=500" if iter == 500
  raise "Bad status = %s" % [status] if status != GSL::SUCCESS
  if status == GSL::SUCCESS
    puts("converged to minimum at") if verbose>0
  end
  #printf(" f() = %7.3f size = %.3f\n", minimizer.fval, minimizer.size) if verbose>0

  x = minimizer.x
  for i in (0..num_vpd-1)
    vpd_map[i].r.elo = x[i]  # Map new ratings from the algorithm
    #print "v[%d]=%0.2f " % [i, v[i]]
  end
  puts "end calc_ratings_fdf " + tostring_now() if verbose > 0

end


# Use AGA-Ratings as a reference
def self.get_log_likelyhood()
  likelyhood = 0
  for name in ::PDB.keys()
    player = ::PDB[name]
    #puts "name=%s" % [name]
    for dayidx in (0...player.vpd.length)
      vpd = player.vpd[dayidx]
      neighbor_vpd_list = []
      neighbor_vpd_list.push(player.vpd[dayidx-1]) if dayidx > 0
      neighbor_vpd_list.push(player.vpd[dayidx+1]) if dayidx < player.vpd.length-1
      for neighbor_vpd in neighbor_vpd_list
        num_draws = virtual_draw_weight(vpd.day, neighbor_vpd.day)
        rd = vpd.r.elo - neighbor_vpd.r.elo
        rd *= Rating::Q
        p = GSL::Sf::log_erfc(rd/Math.sqrt(2)) - Math.log(2)
        likelyhood += num_draws*0.5*p
        p = GSL::Sf::log_erfc(-rd/Math.sqrt(2)) - Math.log(2)
        likelyhood += num_draws*0.5*p
      end
      prior_games = []
      prior_games = player.prior_games if dayidx == 0
      for game in vpd.games + prior_games
        # Only count the game once
        next if game.white_player != player
        # But include the weight as viewed by both players 
        # (In cases of new players the weight is not symmetrical)
        weight = game.get_weight(player)
        weight += game.get_weight(game.get_opponent(player))
        hka = game.handi_komi_advantage(player)
        opp_vpd = game.get_opponent_vpd(player)
        opp_adjusted_r = Rating.new(opp_vpd.r.elo+hka.elo)
        rd = player.r.elo - opp_adjusted_r.elo
        rd *= Rating::Q  # Convert to natural scale
        if game.winner == player
          # Subtracting Math.log(2) isn't strictly necessary but it normalizes the smallest error to zero
          p = GSL::Sf::log_erfc(-rd/Math.sqrt(2)) - Math.log(2)  
        else
          p = GSL::Sf::log_erfc(rd/Math.sqrt(2)) - Math.log(2)
        end
        likelyhood += weight * p
        # p2 - compare erfc method to straight probability of this game outcome method
        #p2 = 1/(1+Math.exp(rd))
        #p2 = 1-p2 if game.winner == player
        #puts "rd=%10.1f p=%10.2f p2=%10.2f g=%s" % [rd, Math.exp(p), p2, game.tostring]
      end
    end
  end
  return -likelyhood
end

# First derivative
def self.get_log_likelyhood_df(df)
  dfidx = -1
  for name in ::PDB.keys().sort { |a,b| a.to_s <=> b.to_s }
    player = ::PDB[name]
    next if player.name[0].class == Symbol
    next if player.anchor_R
    dfidx += 1
    for dayidx in (0...player.vpd.length)
      vpd = player.vpd[dayidx]
      df[dfidx] = 0
      #neighbor_vpd_list = []
      #neighbor_vpd_list.push(player.vpd[dayidx-1]) if dayidx > 0
      #neighbor_vpd_list.push(player.vpd[dayidx+1]) if dayidx < player.vpd.length-1
      #for neighbor_vpd in neighbor_vpd_list
      # TODO add this
      #end
      prior_games = []
      # TODO add prior
      #prior_games = player.prior_games if dayidx == 0
      for game in vpd.games + prior_games
        weight = game.get_weight(player)
        hka = game.handi_komi_advantage(player)
        opp_vpd = game.get_opponent_vpd(player)
        opp_adjusted_r = Rating.new(opp_vpd.r.elo+hka.elo)
        rd = player.r.elo - opp_adjusted_r.elo
        rd = -rd if game.winner != player
        dp = Math.sqrt(2.0/Math::PI) * Math.exp(-rd*rd/2.0 - GSL::Sf::log_erfc(-rd/Math.sqrt(2.0)))
        dp = -dp if game.winner == player
        df[dfidx] += weight*dp
        #puts "rd=%8.1f dp=%10.3f weight=%6.1f g=%s" % [rd, dp, weight, game.tostring]
      end
    end
   end
   return 0
end

# Just take the log of the probability of the game outcome
# Probably less proper than the log_erfc method
# Main problem is it gets a math overflow before it can run Math.log() to avoid that
# Other method uses the GSL log_erfc to do it all together and avoid the overflow
def self.get_direct_log_likelyhood()
  likelyhood = 0
  for name in ::PDB.keys()
    player = ::PDB[name]
    for dayidx in (0...player.vpd.length)
      vpd = player.vpd[dayidx]
      neighbor_vpd_list = []
      neighbor_vpd_list.push(player.vpd[dayidx-1]) if dayidx > 0
      neighbor_vpd_list.push(player.vpd[dayidx+1]) if dayidx < player.vpd.length-1
      for neighbor_vpd in neighbor_vpd_list
        num_draws = virtual_draw_weight(vpd.day, neighbor_vpd.day)
        rd = vpd.r.elo - neighbor_vpd.r.elo
        p = 1/(1+10**(rd/400.0))
        likelyhood += num_draws*0.5*Math.log(p)
        p = 1/(1+10**(-rd/400.0))
        #p = 1-p   How much different would it be to do this instead?
        likelyhood += num_draws*0.5*Math.log(p)
      end
      prior_games = []
      prior_games = player.prior_games if dayidx == 0
      for game in vpd.games + prior_games
        # Only count the game once
        next if game.white_player != player 
        # But include the weight as viewed by both players 
        # (In cases of new players the weight is not symmetrical)
        weight = game.get_weight(player)
        weight += game.get_weight(game.get_opponent(player))
        hka = game.handi_komi_advantage(player)
        opp_vpd = game.get_opponent_vpd(player)
        opp_adjusted_r = Rating.new(opp_vpd.r.elo+hka.elo)
        rd = player.r.elo - opp_adjusted_r.elo
	if game.winner != player
	  p = 1/(1+10**( rd/400.0))
	else
	  p = 1/(1+10**(-rd/400.0))
	end
        likelyhood += weight * Math.log(p)
        #puts "rd=%0.1f p=%f ln(p)=%f g=%s" % [rd, p, Math.log(p), game.tostring]
      end
    end
   end
   return -likelyhood
end


# First derivative
def self.get_direct_log_likelyhood_df(df)
  dfidx = -1
  for name in ::PDB.keys().sort { |a,b| a.to_s <=> b.to_s }
    player = ::PDB[name]
    next if player.name[0].class == Symbol
    next if player.anchor_R
    dfidx += 1
    for dayidx in (0...player.vpd.length)
      vpd = player.vpd[dayidx]
      df[dfidx] = 0
      neighbor_vpd_list = []
      neighbor_vpd_list.push(player.vpd[dayidx-1]) if dayidx > 0
      neighbor_vpd_list.push(player.vpd[dayidx+1]) if dayidx < player.vpd.length-1
      for neighbor_vpd in neighbor_vpd_list
        num_draws = virtual_draw_weight(vpd.day, neighbor_vpd.day)
        rd = vpd.r.elo - neighbor_vpd.r.elo
	exp_nat_rd = Math.exp(rd*Rating::Q)
        p = 1/(1+exp_nat_rd)
        d_logp = -exp_nat_rd/((exp_nat_rd+1)**2)/p
        df[dfidx] += num_draws*0.5*d_logp
	rd = -rd
	exp_nat_rd = Math.exp(rd*Rating::Q)
        p = 1/(1+exp_nat_rd)
        d_logp = -exp_nat_rd/((exp_nat_rd+1)**2)/p
        df[dfidx] += num_draws*0.5*d_logp
      end
      prior_games = []
      prior_games = player.prior_games if dayidx == 0
      for game in vpd.games + prior_games
        weight = game.get_weight(player)
        hka = game.handi_komi_advantage(player)
        opp_vpd = game.get_opponent_vpd(player)
        opp_adjusted_r = Rating.new(opp_vpd.r.elo+hka.elo)
        rd = player.r.elo - opp_adjusted_r.elo
	if game.winner == player
	  rd = -rd
	end
	exp_nat_rd = Math.exp(rd*Rating::Q)
	p = 1/(1+10**(rd/400.0))
        d_logp = -exp_nat_rd/((exp_nat_rd+1)**2)/p
        df[dfidx] += weight*d_logp
        #puts "rd=%0.1f log(p)=%f d_logp=%f g=%s" % [rd, Math.log(p), d_logp, game.tostring]
      end
    end
   end
   return 0
end


def self.add_game(game, iterations=1)
  game.white_player_vpd = game.white_player.add_game(game)
  game.black_player_vpd = game.black_player.add_game(game)
  #mm_iterate(iterations, [game.white_player, game.black_player]) if iterations>0
end


def self.print_pdb()
  puts "print_pdb"
  for name in sorted(::PDB.keys())
    puts ::PDB[name].tostring(1)
  end
end

def self.print_verbose_pdb(verbose=9)
  puts "print_verbose_pdb"
  for name in ::PDB.keys().sort { |a,b| a.to_s <=> b.to_s }
    player = ::PDB[name]
    #next if name.class == Symbol # Skip anchors etc
    print ":" if name.class == Symbol
    puts name
    for vpd in player.vpd
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
	if verbose > 2
	  print " ", game.tostring()
	end
        puts
      end
    end
  end
  puts
end


def self.print_sorted_pdb()
  puts "print_sorted_pdb"
  new_players = []
  i = 1
  # TODO implement <=> for rating class
  for name in ::PDB.keys().sort {|a,b| (a.class==Symbol or b.class==Symbol) ? 0 : PDB[b].rating.elo <=> PDB[a].rating.elo}
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
  puts "MAX_LINK_STRENGTH   = %f" % MAX_LINK_STRENGTH
  puts "MIN_LINK_STRENGTH   = %f" % MIN_LINK_STRENGTH
  puts "LINK_STRENGTH_SCALE = %f" % LINK_STRENGTH_SCALE
  puts "MMITER_TURN_LIMIT   = %d" % MMITER_TURN_LIMIT
end

end  # Module WHR

