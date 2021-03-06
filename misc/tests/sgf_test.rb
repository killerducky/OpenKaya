require "cutest"

require File.expand_path("../lib/sgf", File.dirname(__FILE__))

setup do

end

test "Nodify moves" do
  
  sgf = SGF.new
  node = ";B[ab]"
  sgf.add_move(node)

  assert_equal sgf.move_list, ";B[ab]"

end

test "Should add comment to a node" do

  sgf = SGF.new
  node = ";B[ab]"
  sgf.add_move(node)
  sgf.add_comment("This guy sucks")

  assert_equal sgf.move_list, ";B[ab]"
  assert_equal sgf.to_s ,"(;FF[4];B[ab]C[This guy sucks ])"

  sgf.add_comment("yeah")

  assert_equal sgf.move_list, ";B[ab]"
  assert sgf.to_s.include? "(;FF[4];B[ab]C[This guy sucks yeah ])"

end

test "Should add comment to an empty sgf" do

  sgf = SGF.new
  sgf.add_comment("This guy sucks")

  assert_equal sgf.to_s , "(;FF[4]C[This guy sucks ])"

  sgf.add_comment("yeah")

  assert_equal sgf.to_s, "(;FF[4]C[This guy sucks yeah ])"

end


test "Should add semi-colon between nodes" do

  sgf = SGF.new
  b_node = ";B[ab]"
  w_node = ";W[ac]"
  sgf.add_move(b_node)
  sgf.add_move(w_node)

  assert sgf.move_list =  ";B[ab];W[ac]" 

end

test "Should validate incoming node" do

  sgf = SGF.new
  b_crap = "AG"
  
  assert_raise(RuntimeError) do
    sgf.add_move(b_crap)
  end

  b_bad_time = ";B[qd]BL[12.35]"
  
  assert_raise(RuntimeError) do
    sgf.add_move(b_bad_time)
  end

end

#(;FF[4]GM[1]SZ[19]CA[UTF-8]SO[gokifu.com]BC[kr]WC[kr]EV[7th Korean Wonik Cup Siptan]PB[Ryu Chaehyeong]BR[9p]PW[Kang Dongyun]WR[9p]KM[6.5]DT[2011-09-30]RE[W+R]

#;B[qd];W[pp]

test "Should load an sgf file" do
  filename = "mocks/mock.sgf"
  sgf = SGF.new
  sgf.load_file(filename)
  assert_equal sgf.move_list, ";B[qd];W[pp]"
end

test "should be able to add a time property to a node" do

  sgf = SGF.new
  b_node = ";B[qd]BL[100.553]"
  w_node = ";B[qa]WL[130.553]"

  sgf.add_move(b_node);
  sgf.add_move(w_node);

  assert sgf.move_list =  ";B[ab]BL[100.553];W[ac]WL[130.553]" 

end

test "should explode if try to access invalid property" do
  sgf = SGF.new
  sgf.load_from_string("(;PB[CARLOS]PW[PEPE];B[aa])")

  assert sgf.property(:komi).nil?
end

#(;FF[4]GM[1]SZ[19]CA[UTF-8]SO[gokifu.com]BC[kr]WC[kr]EV[7th Korean Wonik Cup Siptan]PB[Ryu Chaehyeong]BR[9p]PW[Kang Dongyun]WR[9p]KM[6.5]DT[2011-09-30]RE[W+R]


test "Should load a sgf property" do
  filename = "mocks/mock.sgf"
  sgf = SGF.new
  sgf.load_file(filename)

  assert_equal sgf.property(:white_player), "Kang Dongyun"
  assert_equal sgf.property(:black_player), "Ryu Chaehyeong"
  assert_equal sgf.property(:komi), "6.5"
  assert_equal sgf.property(:date), "2011-09-30"
  assert_equal sgf.property(:result), "W+R"
  assert_equal sgf.property(:file_format), "4"
  assert_equal sgf.property(:date), "2011-09-30"
  assert_equal sgf.property(:source), "gokifu.com"
  assert_equal sgf.property(:black_country), "kr"
  assert_equal sgf.property(:white_country), "kr"
  assert_equal sgf.property(:encoding), "UTF-8"
  assert_equal sgf.property(:size), "19"
  assert_equal sgf.property(:event), "7th Korean Wonik Cup Siptan"
  assert_equal sgf.property(:rules), "Japanese"
  assert_equal sgf.property(:time_set), "5x30 byo-yomi"

end

test "should be able to write a full sgf" do

  filename = "mocks/mock.sgf"
  sgf = SGF.new
  sgf.load_file(filename)

  assert_equal sgf.to_s, "(;FF[4]RU[Japanese]TM[1500]OT[5x30 byo-yomi]GM[1]SZ[19]CA[UTF-8]SO[gokifu.com]BC[kr]WC[kr]EV[7th Korean Wonik Cup Siptan]PB[Ryu Chaehyeong]BR[9p]PW[Kang Dongyun]WR[9p]KM[6.5]DT[2011-09-30]RE[W+R];B[qd];W[pp])"

end

test "should give a full sgf string" do

  sgf = SGF.new(";B[ac];W[ed]")

  sgf.write_property(:white_player, "Conan")
  assert_equal sgf.property(:white_player), "Conan"

  sgf.write_property(:black_player,"Conan2")
  assert_equal sgf.property(:black_player), "Conan2"

  assert_equal sgf.to_s, "(;PB[Conan2]PW[Conan]FF[4];B[ac];W[ed])"

end

test 'Should be able to write property' do 

  sgf = SGF.new


  sgf.write_property(:white_player, "Conan")
  assert_equal sgf.property(:white_player), "Conan"

  sgf.write_property(:white_player,"Conan2")
  assert_equal sgf.property(:white_player), "Conan2"

  assert_raise(RuntimeError) do
    sgf.write_property(:total_bs, "bs")
  end

end

test 'Should be able to send a pass move' do

  sgf = SGF.new
  sgf.add_move(";B[]")

  assert sgf.move_list =  ";B[]"

end

test 'Should create a node object' do
  node = Node.new(";B[ac]")

  assert_equal node.color, "B"
  assert_equal node.coordinate, "ac"

  node.add_comment("pepe")
  assert_equal node.comments, "pepe "

  node.add_comment("y yo")
  assert_equal node.comments, "pepe y yo "
end

test 'should create the sgf node list with initialization' do

  sgf = SGF.new(";B[ac];W[ed]")
  assert_equal sgf.move_list, ";B[ac];W[ed]"
  sgf = SGF.new(nil)
  assert_equal sgf.move_list, ""
end

test 'should have handicap node settings' do

  assert !SGF.handi_node(19,5).nil?

end

test 'should recognize if last two moves are pass' do

  sgf = SGF.new(";B[];W[]")
  assert_equal sgf.move_list, ";B[];W[]"
  assert sgf.last_two_moves_are_pass?

  sgf = SGF.new(";B[]BL[500.000];W[]WL[500.000]")
  assert_equal sgf.move_list, ";B[]BL[500.000];W[]WL[500.000]"
  assert sgf.last_two_moves_are_pass?

end

test "should be able to make an sgf with the initial config node properties as params" do

  params = {:size => 9, :white_player => "blanco", :black_player => "negro"}

  sgf = SGF.new(";B[];W[]", params)

  assert_equal sgf.to_s, "(;PB[negro]PW[blanco]SZ[9]FF[4];B[];W[])"
end

test "should be able to parse comments into it" do

  sgf = SGF.new(";B[aa];W[bb]")

  comments = {"0"=>[{"timestamp"=>"[1327727980000]",
                     "user"=>"dp",
                     "rank"=>"[7d]",
                     "message"=>"fgsfgafha",
                     "visibility"=>"",
                     "move_number"=>"0"},
                    {"timestamp"=>"[1327727987000]",
                     "user"=>"conanbatt",
                     "rank"=>"[7d]",
                     "message"=>"aaa",
                     "visibility"=>"",
                     "move_number" =>"0"}
                   ]
             }
  sgf.parse_comments!(comments)

  assert_equal sgf.to_s, "(;FF[4]C[dp[[7d]]: fgsfgafha conanbatt[[7d]]: aaa ];B[aa];W[bb])" 

end
