#require File.expand_path("../test", File.dirname(__FILE__))
require File.expand_path("../strategies/glicko", File.dirname(__FILE__))
require File.expand_path("../strategies/whr", File.dirname(__FILE__))
require File.expand_path("../system", File.dirname(__FILE__))

PDB = {}
PDB[:prior_anchor] = WHR_Player.new(:prior_anchor, Rating.new(2000.0))   # Need to move to whr.rb

puts
puts "winratio"
date = DateTime.parse("2011-09-29")
weight = 10
for win_ratio in (1..2)
  white = PDB["w#{win_ratio}"] = WHR_Player.new("w#{win_ratio}")
  black = PDB["b#{win_ratio}"] = WHR_Player.new("b#{win_ratio}")
  2.times do
    win_ratio.times do
      WHR::AddGame(Game.new(date, white, black, white, weight))
    end
    WHR::AddGame(Game.new(date, white, black, black, weight))
  end
  ::WHR::mmIterate
  diff = Glicko::get_kyudan_rating(white) - Glicko::get_kyudan_rating(black)
  puts "win_ratio=%d diff=%0.2f  <%s>  <%s>" % [win_ratio, diff, Glicko::rating_to_s(white), Glicko::rating_to_s(black)]
end
puts

::WHR::printVerbosePDB()
::WHR::printSortedPDB()
