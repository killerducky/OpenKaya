#require File.expand_path("../test", File.dirname(__FILE__))
require File.expand_path("../strategies/glicko", File.dirname(__FILE__))
require File.expand_path("../strategies/whr", File.dirname(__FILE__))
require File.expand_path("../system", File.dirname(__FILE__))

anchor_name = "_PRIOR_ANCHOR"
PDB[anchor_name] = WHR_Player.new(anchor_name, Rating.new(0.0))   # Need to move to whr.rb

puts
puts "Equal wins"
date = DAYONE
PDB["w"] = WHR_Player.new("w")
PDB["b"] = WHR_Player.new("b")
win_ratio = 3
5.times do
  win_ratio.times do
    AddGame(Game.new(date, PDB["w"], PDB["b"], PDB["w"], PRIOR_WEIGHT))
  end
  AddGame(Game.new(date, PDB["w"], PDB["b"], PDB["b"], PRIOR_WEIGHT))
end
diff = Glicko::get_kyudan_rating(PDB["w"]) - Glicko::get_kyudan_rating(PDB["b"])
puts "diff=%0.2f  <%s>  <%s>" % [diff, Glicko::rating_to_s(PDB["w"]), Glicko::rating_to_s(PDB["b"])]
puts

