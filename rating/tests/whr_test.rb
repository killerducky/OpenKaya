require 'cutest'
require File.expand_path("../strategies/whr", File.dirname(__FILE__))
require File.expand_path("../system", File.dirname(__FILE__))

PDB = {}
EVEN_GAME = ["aga", 0, 7.5]
START_TIME = DateTime.now()   # For performance tracking only
MINIMIZE_METHOD = :fdf

def self.tostring_now()  return "total %0.1fs" % [(DateTime.now() - START_TIME)*24*60*60] end

printf "%s\n" % [tostring_now]
WHR::print_constants()

test "strength spike" do
  puts "strength spike"
  PDB.clear  # Reset PDB each test
  date = DateTime.parse("2011-09-29")
  init_elo_rating = 200
  final_elo_rating = 5000
  #num_games = 110
  num_games = 8
  PDB[:prior_anchor] = WHR_Player.new(:prior_anchor, Rating.new(init_elo_rating))
  p_init  = PDB["i"] = WHR_Player.new("i", Rating.new(init_elo_rating))
  p_final = PDB["f"] = WHR_Player.new("f", Rating.new(final_elo_rating))
  black1 = PDB["b1"] = WHR_Player.new("b1")
  black2 = PDB["b2"] = WHR_Player.new("b2")
  p_init.prior_initialized = true
  p_final.prior_initialized = true
  black1.prior_initialized = true
  black2.prior_initialized = true
  day = 0
  (num_games/2-2).times do
    WHR::add_game(Game.new_even(date+day, p_init, black1, p_init))
    WHR::add_game(Game.new_even(date+day, p_init, black1, black1))
    #WHR::add_game(Game.new_even(date+day, black1, p_init, p_init))
    #WHR::add_game(Game.new_even(date+day, black1, p_init, black1))
    #WHR::add_game(Game.new_even(date+day, black1, p_init, p_init))
    #WHR::add_game(Game.new_even(date+day, p_init, black1, black1))
  end
  day = 10
  (num_games/2+2).times do
    WHR::add_game(Game.new_even(date+day, p_final, black2, p_final))
    WHR::add_game(Game.new_even(date+day, p_final, black2, black2))
    #WHR::add_game(Game.new_even(date+day, black2, p_final, p_final))
    #WHR::add_game(Game.new_even(date+day, black2, p_final, black2))
    #WHR::add_game(Game.new_even(date+day, p_final, black2, p_final))
    #WHR::add_game(Game.new_even(date+day, black2, p_final, black2))
  end
  black1.vpd[0].r.elo = 210
  black2.vpd[0].r.elo = 220
  puts WHR::tostring_now()
  puts "get_direct_log_likelyhood=%f" % [WHR::get_direct_log_likelyhood]
  WHR::print_verbose_pdb(9)
  WHR::minimize()
  puts "get_direct_log_likelyhood=%f" % [WHR::get_direct_log_likelyhood]
  WHR::print_verbose_pdb(1)
  #puts "start mm_iterate=%s" % [WHR::tostring_now()]
  #WHR::mm_iterate()
  #puts "get_direct_log_likelyhood=%f" % [WHR::get_direct_log_likelyhood]
  #puts black.tostring()
  #puts p_init.tostring()
  #puts p_final.tostring()
  #puts PDB[:prior_anchor].tostring()
end

test "win_ratio" do
  PDB.clear  # Reset PDB each test
  puts
  puts "win_ratio"
  date = DateTime.parse("2011-09-29")
  init_aga_rating = -25
  for win_ratio in (1..9)
  for stronger in [:black, :white]
    white = PDB["w"] = WHR_Player.new("w", Rating.new_aga_rating(init_aga_rating))
    black = PDB["b"] = WHR_Player.new("b")
    white.prior_initialized = true
    black.prior_initialized = true
    3.times do
      win_ratio.times do
        WHR::add_game(Game.new_even(date, white, black, stronger==:black ? black : white),0)
      end
      WHR::add_game(Game.new_even(date, white, black, stronger==:black ? white : black),0)
      puts black.tostring()
      date += 1
    end
    printf "win_ratio=%d stronger=%s\n" % [win_ratio, stronger]
    WHR::minimize()
    puts black.tostring(1)
    WHR::print_sorted_pdb()
    WHR::print_verbose_pdb(1)
    ratio = white.rating.gamma / black.rating.gamma
    ratio = 1/ratio if stronger == :black
    ratio_of_ratio  = ratio/win_ratio
    puts "stronger=%s win_ratio=%f ratio=%f 1/ratio=%f ratio_of_ratio=%f" % [stronger, win_ratio, ratio, 1/ratio, ratio_of_ratio]
    assert ((1.0 - ratio_of_ratio).abs < 0.1)
  end
  end
  puts
  puts "end win_ratio"
end

def multi_test(test)
  PDB.clear  # Reset PDB each test
  date = DateTime.parse("2011-09-29")
  PDB[:prior_anchor]  = WHR_Player.new(:prior_anchor, Rating.new(0))   # Need to move to whr.rb
  PDB[:mid_rating]    = WHR_Player.new(:mid_rating  , Rating.new(1000))
  PDB[:high_rating]   = WHR_Player.new(:high_rating , Rating.new(2000))
  PDB["yoyoma"]  = WHR_Player.new("yoyoma")
  PDB["killerd"] = WHR_Player.new("killerd")
  if (test[0] == "new_strong")
    day = 0
    num_games = 20
    WHR::add_game(Game.new_even(date+day, PDB["yoyoma"], PDB[:mid_rating], PDB[:mid_rating]))
    puts PDB["yoyoma"].tostring(rtype)
    num_games.times do
      WHR::add_game(Game.new_even(date+day, PDB["yoyoma"], PDB[:high_rating], PDB["yoyoma"]))
      puts PDB["yoyoma"].tostring(rtype)
    end
  elsif (test[0] == "low_confidence_corner")
    day = 0
    WHR::add_game(Game.new_even(date+day, PDB["yoyoma"], PDB[:mid_rating], PDB["yoyoma"]))
    puts PDB["yoyoma"].tostring(rtype, 1)
    WHR::add_game(Game.new_even(date+day, PDB["yoyoma"], PDB[:mid_rating], PDB[:mid_rating]))
    puts PDB["yoyoma"].tostring(rtype, 1)
    day = 365*5  # 5 years later
    3.times do
      WHR::add_game(Game.new_even(date+day, PDB["yoyoma"], PDB[:high_rating], PDB["yoyoma"]))
      puts PDB["yoyoma"].tostring(rtype, 1)
    end
    puts
    3.times do
      WHR::add_game(Game.new_even(date+day, PDB["yoyoma"], PDB[:high_rating], PDB[:high_rating]))
    end
  elsif (test[0] == "1stone")
    (testname, prior_games_per_day, prior_winrate, break_days, post_games_per_day, post_winrate) = test
    puts "1stone prior prior_games_per_day=%d prior_winrate=%0.3f" % [prior_games_per_day, prior_winrate]
    for day in (0..179)
      WHR::add_game(Game.new_even(date+day, PDB["yoyoma"], PDB[:mid_rating], PDB["yoyoma"], prior_games_per_day*prior_winrate))
      WHR::add_game(Game.new_even(date+day, PDB["yoyoma"], PDB[:mid_rating], PDB[:mid_rating], prior_games_per_day*(1.0-prior_winrate)))
    end
    puts "1stone post  post_games_per_day=%d post_winrate=%0.3f break_days=%d" % [post_games_per_day, post_winrate, break_days]
    rating = {}
    for day in (180+break_days..360+break_days-1)
      WHR::add_game(Game.new_even(date+day, PDB["yoyoma"], PDB[:mid_rating], PDB["yoyoma"], post_games_per_day*post_winrate))
      WHR::add_game(Game.new_even(date+day, PDB["yoyoma"], PDB[:mid_rating], PDB[:mid_rating], post_games_per_day*(1.0-post_winrate)))
      rating[day] = PDB["yoyoma"].getVpd(day).R.kyudan
      break if rating[day] > 1.5 # Stop after improving by a half stone
    end
    for day in sorted(rating.keys())
      puts "day=%d R=%0.2f" % [day-179, rating[day]]
    end
  elsif (test[0]== "marathon_day")
    (testname, prior_games_per_day, prior_winrate, break_days, post_winrate) = test
    puts "marathon_day prior prior_games_per_day=%0.2f prior_winrate=%0.3f" % [prior_games_per_day, prior_winrate]
    for day in (0..180)
      WHR::add_game(Game.new_even(date+day, PDB["yoyoma"], PDB[:mid_rating], PDB["yoyoma"], prior_games_per_day*prior_winrate))
      WHR::add_game(Game.new_even(date+day, PDB["yoyoma"], PDB[:mid_rating], PDB[:mid_rating], prior_games_per_day*(1.0-prior_winrate)))
    end
    puts "marathon_day post  post_winrate=%0.3f break_days=%d" % [post_winrate, break_days]
    rating = {}
    day = 180+break_days
    for gamenum in (1..100)
      WHR::add_game(Game.new_even(date+day, PDB["yoyoma"], PDB[:mid_rating], PDB["yoyoma"], 1.0*post_winrate))
      WHR::add_game(Game.new_even(date+day, PDB["yoyoma"], PDB[:mid_rating], PDB[:mid_rating], 1.0*(1.0-post_winrate)))
      rating[gamenum] = PDB["yoyoma"].rating.kyudan
      break if rating[gamenum] > 2.5 # Stop after improving by a 1.5 stones
    end
    for gamenum in rating.keys().sort
      puts "gamenum=%d R=%0.2f" % [gamenum, rating[gamenum]]
    end
  end
  WHR::minimize()
  WHR::print_verbose_pdb(1)
  WHR::print_sorted_pdb()
end

test "Equal wins" do
  puts
  puts "Equal wins"
  PDB.clear  # Reset PDB each test
  date = DateTime.parse("2011-10-01")
  prev_gv = gv = {}
  for init_aga_rating in [-25.5, -1.5, 5.5]
    for (handi, komi) in [[0, 7.5], [0, 0.5], [0, -6.5], [2, 0.5], [6, 0.5]]
      plr_w = PDB[:w ] = WHR_Player.new(:w , Rating.new_aga_rating(init_aga_rating))
      plr_b = PDB["b"] = WHR_Player.new("b")
      plr_w.prior_initialized = true  # Bypass prior logic
      plr_b.prior_initialized = true  # Bypass prior logic
      for num_games in (1..3)
        WHR::add_game(Game.new(date, plr_w, plr_b, "aga", handi, komi, plr_b),0)
        WHR::add_game(Game.new(date, plr_w, plr_b, "aga", handi, komi, plr_w),0)
        WHR::minimize()
        diff = plr_w.r.kyudan - plr_b.r.kyudan - Rating.advantage_in_stones(handi, komi, 7.5)
        puts "h=%d k=%0f diff=%0.2f  %f - %f - %f" % [handi, komi, diff, plr_w.r.kyudan, plr_b.r.kyudan, Rating.advantage_in_stones(handi, komi, 7.5)]
        assert (diff.abs < 0.05)             # Ratings should almost match the handicap advantage
        #tmp_vars = WHR::compute_variance(plr_b)
        #gv[num_games] = tmp_vars[-1].GV
        gv[num_games] = -1
        puts "elo=%f num_games=%d gv=%f" % [plr_b.vpd[-1].r.elo, num_games, gv[num_games]]
        assert ((gv[num_games]-prev_gv[num_games]).abs < 0.01) if prev_gv[num_games]  # Variance should not depend on init_aga_rating, handi, or komi
        prev_gv[num_games] = gv[num_games]
      end
    end
  end
  puts "end equal wins"
end

class Hash
  def self.recursive
    new { |hash, key| hash[key] = recursive }
  end
end

test "Ratings response" do
  puts
  puts "Ratings response"
  #PREV_GAMES = 30
  #POST_GAMES = 30
  PREV_GAMES = 20
  POST_GAMES = 20
  #
  # TODO: Measure rate that Variance decreases
  # TODO: Make sure new player ratings move fast
  # TODO: Make sure new players do not impact exisiting ones as much until they get more history
  #
  key_results = Hash.recursive
  puts "New person winning 100%, all even games against solid opponents with same rating as the new person"
  for init_aga_rating in [8.0, -8.0]
    for days_rest in [0, 1, 7, 30]
      PDB.clear  # Reset PDB each test
      date = DateTime.parse("2011-09-24")
      puts "init_aga_rating=#{init_aga_rating} days_rest=#{days_rest}"
     #puts "  #  newR   95%   newAGA    95%      dR  dKD  (1/dKD)"
      puts "  #  newR  dKD  (1/dKD)"
      plr_anchor = PDB[:anchor] = WHR_Player.new(:anchor, Rating.new_aga_rating(init_aga_rating))
      plr_b      = PDB["b"]     = WHR_Player.new("b")
      plr_b.prior_initialized  = true
      # At first they were even
      PREV_GAMES.times do
        WHR::add_game(Game.new_even(date, plr_anchor, plr_b, plr_anchor),0)
        WHR::add_game(Game.new_even(date, plr_anchor, plr_b, plr_b ),0)
        date += days_rest
      end
      puts "minimize on even games"
      WHR::minimize()
      WHR::print_sorted_pdb()
      WHR::print_verbose_pdb(9)
      for i in 1..POST_GAMES
        prev_rating = plr_b.rating.dup
        anchor_name = "anchor%d"%[i]
        plr_anchor = WHR_Player.new(anchor_name, prev_rating.dup)  # Keep making new anchors to play against
        PDB[anchor_name] = plr_anchor
        # To avoid going across the weird 5k-2d transition area,
        # do win streak for dans but loss streak for kyus
        WHR::add_game(Game.new_even(date, plr_anchor, plr_b, init_aga_rating >= 0 ? plr_b : plr_anchor))
        printf "init_aga_rating=#{init_aga_rating} days_rest=#{days_rest} postgames = %d\n" % [i]
        WHR::print_sorted_pdb()
        WHR::print_verbose_pdb(9)
        WHR::minimize()
        dKD = (plr_b.rating.kyudan - prev_rating.kyudan).abs
        puts "%3d %6.2f  %4.2f (%4.1f)" % [i, plr_b.rating.kyudan, dKD, 1/dKD]
        key_results[init_aga_rating][:dKD_init     ][days_rest] = dKD    if i==1
        # Replace this with variance equivalent
        #key_results[init_aga_rating][:numgame_minrd][days_rest] = i      if plr_b.rd==Glicko::MIN_RD and key_results[init_aga_rating][:numgame_minrd][days_rest] == {}
        key_results[init_aga_rating][:dKD_final    ][days_rest] = dKD    if i==POST_GAMES
        key_results[init_aga_rating][:dKD_inv_final][days_rest] = 1/dKD  if i==POST_GAMES
        date += days_rest  # new person waits this many days before playing again
      end
      puts
    end
  end
  WHR::print_verbose_pdb()
  for init_aga_rating,v in key_results.each
    for k,v in v.each
      for days_rest,v in v.each
        print "%15s %4.1f %6.2f %6.2f\n" % [k, days_rest, init_aga_rating, v]
      end
    end
  end
end

#               prior         post
#              gpd wr  break gpd wr
#multi_test(["1stone", 1, 0.5, 0,   10, 0.79])
#multi_test(["1stone", 1, 0.5, 0,   1, 0.79])

#                     prior           post
#                    gpd wr    break   wr
#multi_test(["marathon_day",   1, 0.5, 0,    1.0])   # Increasing prior sizes
#multi_test(["marathon_day",  10, 0.5, 0,    1.0])
#multi_test(["marathon_day", 100, 0.5, 0,    1.0])

#multi_test(["marathon_day",  10, 0.5,   0,    1.0])  # Increasing break time
#multi_test(["marathon_day",  10, 0.5,  10,    1.0])  # Increasing break time
#multi_test(["marathon_day",  10, 0.5,  30,    1.0])  # Increasing break time
#multi_test(["marathon_day",  10, 0.5, 365,    1.0])  # Increasing break time

#multi_test(["marathon_day",  10, 0.5,  0, 0.79])  # Increasing break time, not undefeated
#multi_test(["marathon_day",  10, 0.5, 10, 0.79])  # Increasing break time, not undefeated
#multi_test(["marathon_day",  10, 0.5, 30, 0.79])  # Increasing break time, not undefeated

#multi_test(["marathon_day",  0.01, 0.5, 0, 1.0])  # Increasing break time

printf "%s\n" % [tostring_now]
