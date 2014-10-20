#!/usr/bin/ruby

class Host
  
  attr_reader :name, :typ, :aliases
  attr_writer :type

  def initialize(name, typ, aliases)
    @name = name
    @typ = typ
    @aliases = aliases
  end
end

if ARGV[0] == nil or ARGV[1] == nil
  puts "usage: #$0 <aliases file> <traces directory>"
  exit
end

Null_IP = "0.0.0.0"

hosts = Hash.new
links = Hash.new
ip_to_name = Hash.new
sources = Hash.new

aliased = Hash.new
aliased_names = Hash.new

s_counter = 0
e_counter = 0
r_counter = 0
ali_counter = 0

alias_file = File.open(ARGV[0])
traces = Dir.new(ARGV[1])

alias_file.each_line do |line|
  line.split(" ").each do |ip|
    if aliased[ip] != nil
      $stderr.puts "error: #{ip} already has an alias"
      exit
    end
    aliased[ip] = ali_counter
  end
  ali_counter += 1
end

prev_ip = ""

traces.each do |fname|
  next if fname == "." or fname == ".."
  $stderr.puts "  " + fname

  fname =~ /^trace\.out\.(.*)$/
  dns = $1
  `host #{dns}` =~ /has address (.*)$/
  ip = $1

  if ip == nil
    $stderr.puts "#{fname} didn't resolve"
    next
  end

  if aliased[ip] != nil
    # does the alias have a name?
    name = aliased_names[aliased[ip]]
    # create name and map all same aliases to that name
    if name == nil
      name = "S#{s_counter}"
      aliased_names[aliased[ip]] = name
      s_counter += 1

      temp_aliases = Array.new

      # create a new host with all aliases
      # and map all aliases to the same name
      ip_num = aliased[ip]
      aliased.each_key do |k|
	if aliased[k] == ip_num
	  ip_to_name[k] = name
	  temp_aliases << k
	end
      end
      hosts[name] = Host.new(name, :S, temp_aliases)
    end

  else  # not an alias
    if ip_to_name[ip] == nil
      name = "S#{s_counter}"
      ip_to_name[ip] = name
      s_counter += 1
      hosts[name] = Host.new(name, :S, ip)
    end
  end

  source_ip = ip

  infile = File.open(ARGV[1] + "/" + fname)
  infile.each_line do |line|

    # handle "destination: " lines 
    if line =~ /^destination: (.*) hops/
      ip = $1

      # four cases: aliased or not, and has name or not
      # first determine if it aliased
      if aliased[ip] != nil
	# does the alias have a name?
	name = aliased_names[aliased[ip]]
	# create name and map all same aliases to that name
	if name == nil
	  name = "E#{e_counter}"
	  aliased_names[aliased[ip]] = name
	  e_counter += 1

	  temp_aliases = Array.new

	  # create a new host with all aliases
	  # and map all aliases to the same name
	  ip_num = aliased[ip]
	  aliased.each_key do |k|
	    if aliased[k] == ip_num
	      ip_to_name[k] = name
	      temp_aliases << k
	    end
	  end
	  hosts[name] = Host.new(name, :E, temp_aliases)
	end

      else  # not an alias
	if ip_to_name[ip] == nil
	  name = "E#{e_counter}"
	  ip_to_name[ip] = name
	  e_counter += 1
	  hosts[name] = Host.new(name, :E, ip)
	end
      end
   
      prev_ip = source_ip

    # parse lines that are links
    elsif line =~ /\d+: ([^\s]+) /
      ip = $1
      if ip == Null_IP
	prev_ip = ip
	next
      end

      # first handle the router part
      if aliased[ip] != nil
	name = aliased_names[aliased[ip]]
	if name == nil
	  name = "R#{r_counter}"
	  aliased_names[aliased[ip]] = name
	  r_counter += 1
	  temp_aliases = Array.new
	  ip_num = aliased[ip]
	  aliased.each_key do |k|
	    if aliased[k] == ip_num
	      ip_to_name[k] = name
	      temp_aliases << k
	    end
	  end
	  hosts[name] = Host.new(name, :R, temp_aliases)
	end

      else
	if ip_to_name[ip] == nil
	  name = "R#{r_counter}"
	  ip_to_name[ip] = name
	  r_counter += 1
	  hosts[name] = Host.new(name, :R, ip)
	end
      end

      # now handle the link part

      if ip != Null_IP and prev_ip != Null_IP
	if prev_ip < ip
	  index = prev_ip + "-" + ip
	else
	  index = ip + "-" + prev_ip
	end
	if links[index] == nil
	  links[index] = "Link  #{ip_to_name[prev_ip]}:#{prev_ip} -- #{ip_to_name[ip]}:#{ip} : TR"
	end
      end
      prev_ip = ip
      
    end
  end
end


# print endhosts
hosts.each do |k, v|
  if v.typ == :E
    if v.aliases.kind_of? String
      puts "Endhost #{v.name} nAlly=1 #{v.aliases}"
    elsif v.aliases.kind_of? Array
      puts "Endhost #{v.name} nAlly=#{v.aliases.size} #{v.aliases.join(' ')}"
    else
      puts "unknown endhost type"
      exit
    end
  end
end

# print routers
hosts.each do |k, v|
  if v.typ == :R
    if v.aliases.kind_of? String
      puts "Router #{v.name} nAlly=1 #{v.aliases}"
    elsif v.aliases.kind_of? Array
      puts "Router #{v.name} nAlly=#{v.aliases.size} #{v.aliases.join(' ')}"
    else
      puts "unknown router type"
      exit
    end
  end
end

# print sources
hosts.each do |k, v|
  if v.typ == :S
    if v.aliases.kind_of? String
      puts "Source #{v.name} nAlly=1 #{v.aliases}"
    elsif v.aliases.kind_of? Array
      puts "Source #{v.name} nAlly=#{v.aliases.size} #{v.aliases.join(' ')}"
    else
      puts "unknown source type"
      exit
    end
  end
end

# print links
links.each do |k, v|
  puts v
end
