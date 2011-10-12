require 'cutest'
require File.expand_path("../strategies/whr", File.dirname(__FILE__))
require File.expand_path("../system", File.dirname(__FILE__))

PDB = {}
PDB[:prior_anchor] = WHR_Player.new(:prior_anchor, Rating.new(0))
EVEN_GAME = ["aga", 0, 7.5]
START_TIME = DateTime.now()   # For performance tracking only

def self.tostring_now()  return "total %0.1fs" % [(DateTime.now() - START_TIME)*24*60*60] end

def read_data_set(filename)
  set = []
  File.open(filename, "r") do |infile|
    while (line = infile.gets)
      next if line =~ /^\s*#/  # Skip comments
      next if line =~ /^\s*$/  # Skip empty lines
      datetime, w, b, winner, weight = line.split(",")
      # TODO add weight
      datetime = DateTime.parse(datetime)
      PDB[w] = WHR_Player.new(w) unless PDB.has_key?(w)
      PDB[b] = WHR_Player.new(b) unless PDB.has_key?(b)
      w = PDB[w]
      b = PDB[b]
      WHR::add_game(Game.new_even(datetime, w, b, PDB[winner]))
    end
  end
end


printf "%s\n" % [tostring_now]
WHR::print_constants()
read_data_set("data/tlpd_short.csv")
WHR::minimize()
WHR::print_sorted_pdb()
WHR::print_verbose_pdb(9)
printf "%s\n" % [tostring_now]
