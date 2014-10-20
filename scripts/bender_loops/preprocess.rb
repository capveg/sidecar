#!/usr/bin/ruby

#############################
## BE SURE TO DO A sort -u ON THE RESULTING DATA
#############################

router_file = File.open("routers")
source_file = File.open("sources")
link_file = File.open("links")

asfile = IO.popen("~/swork/undns/originForIP", "r+")
stub_ASes = Hash.new
routers = Hash.new
verbose = false

source_file.each_line do |line|
  tokens = line.split(/ /)
  tokens[3..-1].each do |ip|
    ip.chomp!
    asfile.puts ip
    as = asfile.gets
    as.chomp!
    stub_ASes[as] = true unless as == "0" or as.length == 0
  end
end
source_file.close

router_file.each_line do |line|
  tokens = line.split(" ")
  prev_as = ""
  glom = true
  tokens[3..-1].each do |ip|
    ip.chomp!
    asfile.puts ip
    as = asfile.gets
    as.chomp!
    puts "stub[#{as}] = #{stub_ASes[as]}" if verbose
    if stub_ASes[as] == nil or as == "0"
      puts "not glomming #{line} as #{prev_as}" if verbose
      glom = false
      break
    end
    if prev_as == ""
      prev_as = as
    elsif prev_as != as
      glom = false
      break
    end
  end
  if glom == true
    puts "glomming #{line} as #{prev_as}" if verbose
    routers[tokens[1]] = "AS" + prev_as
  end
end
router_file.close

link_file.each_line do |line|
  tokens = line.split(/\s+|:/)
  next if tokens[-1] == "UNKNOWN"

  ip1 = tokens[2]
  ip2 = tokens[5]
  next if ip1 == ip2
  name1 = tokens[1]
  name2 = tokens[4]
  puts "|#{name1} => #{routers[name1]} :: #{name2} => #{routers[name2]}|" if verbose

  # see if this is a link to a router in a stub AS
  if (routers[name1] != nil)
    name1 = routers[name1]
  end

  if (routers[name2] != nil)
    name2 = routers[name2]
  end

  # convert stub AS links to their AS numbers
  asfile.puts ip1
  as1 = asfile.gets.chomp!
  if stub_ASes[as1]
    name1 = "AS" + as1
  end

  asfile.puts ip2
  as2 = asfile.gets.chomp!
  if stub_ASes[as2]
    name2 = "AS" + as2
  end

  # avoid duplicates
  if name1 < name2
    puts "#{name1} #{name2}"
  elsif name2 < name1
    puts "#{name2} #{name1}"
  end
end
link_file.close
