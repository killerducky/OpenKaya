#require File.expand_path("../test", File.dirname(__FILE__))
require File.expand_path("../strategies/glicko", File.dirname(__FILE__))
require File.expand_path("../strategies/whr", File.dirname(__FILE__))
require File.expand_path("../system", File.dirname(__FILE__))

PDB = {}

def win_ratio()
  PDB.clear  # Reset PDB each test
  PDB[:prior_anchor] = WHR_Player.new(:prior_anchor, Rating.new(2000.0))   # Need to move to whr.rb
  puts
  puts "win_ratio"
  date = DateTime.parse("2011-09-29")
  weight = 10
  for win_ratio in (1..9)
    white = PDB["w#{win_ratio}"] = WHR_Player.new("w#{win_ratio}")
    black = PDB["b#{win_ratio}"] = WHR_Player.new("b#{win_ratio}")
    3.times do
      win_ratio.times do
        WHR::add_game(Game.new(date, white, black, white, weight))
      end
      WHR::add_game(Game.new(date, white, black, black, weight))
    end
    ::WHR::mm_iterate
    diff = white.rating.kyudan_rating - black.rating.kyudan_rating
    puts "win_ratio=%d diff=%0.2f  <%6.0f %6.2f>  <%6.0f %6.2f>" % [win_ratio, diff, white.rating.elo, white.rating.aga_rating, black.rating.elo, black.rating.aga_rating]
  end
  puts
  #::WHR::print_verbose_PDB()
  ::WHR::print_sorted_PDB()
end


def test(test)
  PDB.clear  # Reset PDB each test
  date = DateTime.parse("2011-09-29")
  PDB[:prior_anchor]  = WHR_Player.new(:prior_anchor, Rating.new(0))   # Need to move to whr.rb
  PDB[:mid_rating]    = WHR_Player.new(:mid_rating  , Rating.new(1000))
  PDB[:high_rating]   = WHR_Player.new(:high_rating , Rating.new(2000))
  PDB["yoyoma"]  = WHR_Player.new("yoyoma")
  PDB["killerd"] = WHR_Player.new("killerd")
  if (test[0] == "even")
    for day in (0..2)
      3.times do
        WHR::add_game(Game.new(date+day, PDB["yoyoma"], PDB["killerd"], PDB["yoyoma"]))
        WHR::add_game(Game.new(date+day, PDB["yoyoma"], PDB["killerd"], PDB["killerd"]))
      end
    end
  elsif (test[0] == "4:1")
    for day in (0..2)
      3.times do
        WHR::add_game(Game.new(date+day, PDB["yoyoma"], PDB["killerd"], PDB["yoyoma"]))
        WHR::add_game(Game.new(date+day, PDB["yoyoma"], PDB["killerd"], PDB["yoyoma"]))
        WHR::add_game(Game.new(date+day, PDB["yoyoma"], PDB["killerd"], PDB["yoyoma"]))
        WHR::add_game(Game.new(date+day, PDB["yoyoma"], PDB["killerd"], PDB["yoyoma"]))
        WHR::add_game(Game.new(date+day, PDB["yoyoma"], PDB["killerd"], PDB["killerd"]))
      end
    end
  elsif (test[0] == "improve_spike")
    day = 0
    num_games = 10
    (num_games/2).times do
      WHR::add_game(Game.new(date+day, PDB["yoyoma"], PDB[:mid_rating], PDB["yoyoma"]))
      WHR::add_game(Game.new(date+day, PDB["yoyoma"], PDB[:mid_rating], PDB[:mid_rating]))
      WHR::add_game(Game.new(date+day, PDB["killerd"], PDB[:mid_rating], PDB["killerd"]))
      WHR::add_game(Game.new(date+day, PDB["killerd"], PDB[:mid_rating], PDB[:mid_rating]))
    end
    day = 1
    (num_games/2).times do
      WHR::add_game(Game.new(date+day, PDB["killerd"], PDB[:high_rating], PDB["killerd"]))
      WHR::add_game(Game.new(date+day, PDB["killerd"], PDB[:high_rating], PDB[:high_rating]))
    end
    # Add in non-consequential (low weight) playerday in middle
    # This experiment showed that putting the extra vpd in changed the results by ~0.5 stone
    # Ideally the link_strength should scale such that it has no impact.
    # Not sure if that is really possible though.
    #for day in (16..17)
    #   WHR::add_game(Game.new(date+day, PDB["yoyoma"], PDB[:high_rating], PDB["yoyoma"], 0.00001))
    #   WHR::add_game(Game.new(date+day, PDB["yoyoma"], PDB[:high_rating], PDB[:high_rating], 0.00001))
    day = 32
    (num_games/2).times do
      WHR::add_game(Game.new(date+day, PDB["yoyoma"], PDB[:high_rating], PDB["yoyoma"]))
      WHR::add_game(Game.new(date+day, PDB["yoyoma"], PDB[:high_rating], PDB[:high_rating]))
    end
  elsif (test[0] == "new_strong")
    day = 0
    num_games = 20
    WHR::add_game(Game.new(date+day, PDB["yoyoma"], PDB[:mid_rating], PDB[:mid_rating]))
    puts PDB["yoyoma"].tostring(rtype)
    num_games.times do
      WHR::add_game(Game.new(date+day, PDB["yoyoma"], PDB[:high_rating], PDB["yoyoma"]))
      puts PDB["yoyoma"].tostring(rtype)
    end
  elsif (test[0] == "strength_spike")
    day = 0
    num_games = 110
    (num_games/2-2).times do
      WHR::add_game(Game.new(date+day, PDB["yoyoma"], PDB[:mid_rating], PDB["yoyoma"]))
      WHR::add_game(Game.new(date+day, PDB["yoyoma"], PDB[:mid_rating], PDB[:mid_rating]))
    end
    day = 100
    (num_games/2+2).times do
      WHR::add_game(Game.new(date+day, PDB['yoyoma'], PDB[:high_rating], PDB["yoyoma"]))
      WHR::add_game(Game.new(date+day, PDB['yoyoma'], PDB[:high_rating], PDB[:high_rating]))
    end
  elsif (test[0] == "low_confidence_corner")
    day = 0
    WHR::add_game(Game.new(date+day, PDB["yoyoma"], PDB[:mid_rating], PDB["yoyoma"]))
    puts PDB["yoyoma"].tostring(rtype, 1)
    WHR::add_game(Game.new(date+day, PDB["yoyoma"], PDB[:mid_rating], PDB[:mid_rating]))
    puts PDB["yoyoma"].tostring(rtype, 1)
    day = 365*5  # 5 years later
    3.times do
      WHR::add_game(Game.new(date+day, PDB["yoyoma"], PDB[:high_rating], PDB["yoyoma"]))
      puts PDB["yoyoma"].tostring(rtype, 1)
    end
    puts
    3.times do
      WHR::add_game(Game.new(date+day, PDB["yoyoma"], PDB[:high_rating], PDB[:high_rating]))
    end
  elsif (test[0] == "1stone")
    (testname, prior_games_per_day, prior_winrate, break_days, post_games_per_day, post_winrate) = test
    puts "1stone prior prior_games_per_day=%d prior_winrate=%0.3f" % [prior_games_per_day, prior_winrate]
    for day in (0..179)
      WHR::add_game(Game.new(date+day, PDB["yoyoma"], PDB[:mid_rating], PDB["yoyoma"], prior_games_per_day*prior_winrate))
      WHR::add_game(Game.new(date+day, PDB["yoyoma"], PDB[:mid_rating], PDB[:mid_rating], prior_games_per_day*(1.0-prior_winrate)))
    end
    puts "1stone post  post_games_per_day=%d post_winrate=%0.3f break_days=%d" % [post_games_per_day, post_winrate, break_days]
    rating = {}
    for day in (180+break_days..360+break_days-1)
      WHR::add_game(Game.new(date+day, PDB["yoyoma"], PDB[:mid_rating], PDB["yoyoma"], post_games_per_day*post_winrate))
      WHR::add_game(Game.new(date+day, PDB["yoyoma"], PDB[:mid_rating], PDB[:mid_rating], post_games_per_day*(1.0-post_winrate)))
      rating[day] = PDB["yoyoma"].getVpd(day).R.kyudan_rating
      break if rating[day] > 1.5 # Stop after improving by a half stone
    end
    for day in sorted(rating.keys())
      puts "day=%d R=%0.2f" % [day-179, rating[day]]
    end
  elsif (test[0]== "marathon_day")
    (testname, prior_games_per_day, prior_winrate, break_days, post_winrate) = test
    puts "marathon_day prior prior_games_per_day=%0.2f prior_winrate=%0.3f" % [prior_games_per_day, prior_winrate]
    for day in (0..180)
      WHR::add_game(Game.new(date+day, PDB["yoyoma"], PDB[:mid_rating], PDB["yoyoma"], prior_games_per_day*prior_winrate))
      WHR::add_game(Game.new(date+day, PDB["yoyoma"], PDB[:mid_rating], PDB[:mid_rating], prior_games_per_day*(1.0-prior_winrate)))
    end
    puts "marathon_day post  post_winrate=%0.3f break_days=%d" % [post_winrate, break_days]
    rating = {}
    day = 180+break_days
    for gamenum in (1..100)
      WHR::add_game(Game.new(date+day, PDB["yoyoma"], PDB[:mid_rating], PDB["yoyoma"], 1.0*post_winrate))
      WHR::add_game(Game.new(date+day, PDB["yoyoma"], PDB[:mid_rating], PDB[:mid_rating], 1.0*(1.0-post_winrate)))
      rating[gamenum] = PDB["yoyoma"].rating.kyudan_rating
      break if rating[gamenum] > 2.5 # Stop after improving by a 1.5 stones
    end
    for gamenum in rating.keys().sort
      puts "gamenum=%d R=%0.2f" % [gamenum, rating[gamenum]]
    end
  end
  ::WHR::mm_iterate
  ::WHR::print_verbose_PDB(1)
  ::WHR::print_sorted_PDB()
end


WHR::print_constants()
win_ratio()

test (["strength_spike"])

#               prior         post
#              gpd wr  break gpd wr
#test(["1stone", 1, 0.5, 0,   10, 0.79])
#test(["1stone", 1, 0.5, 0,   1, 0.79])

#                     prior           post
#                    gpd wr    break   wr
#test(["marathon_day",   1, 0.5, 0,    1.0])   # Increasing prior sizes
#test(["marathon_day",  10, 0.5, 0,    1.0])
#test(["marathon_day", 100, 0.5, 0,    1.0])

#test(["marathon_day",  10, 0.5,   0,    1.0])  # Increasing break time
#test(["marathon_day",  10, 0.5,  10,    1.0])  # Increasing break time
#test(["marathon_day",  10, 0.5,  30,    1.0])  # Increasing break time
#test(["marathon_day",  10, 0.5, 365,    1.0])  # Increasing break time

#test(["marathon_day",  10, 0.5,  0, 0.79])  # Increasing break time, not undefeated
#test(["marathon_day",  10, 0.5, 10, 0.79])  # Increasing break time, not undefeated
#test(["marathon_day",  10, 0.5, 30, 0.79])  # Increasing break time, not undefeated

#test(["marathon_day",  0.01, 0.5, 0, 1.0])  # Increasing break time

