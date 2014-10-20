#!/usr/bin/ruby

Aliases = File.open("nlr-facts.dlv").select { |ln| ln =~ /^alias/ }.map { |ln| if ln =~ /alias\(([\d\.]+),([\d\.]+),foo\) % (\S+)/ then [ $1, $2, $3 ] else nil end }

labels = Hash.new

class NoRewriteHash < Hash
  def []=(k,v)
    if self[k] != nil && self[k] != v then
      raise "can't make #{k} be #{v} when it's already #{self[k]}"
    end
    super(k,v)
  end
end

labels = NoRewriteHash.new

Aliases.each { |a,b,label|
  begin
    labels[a] = label
    labels[b] = label
  rescue  => e
    puts e
  end


}

# labels.each { |k,v|
   # puts "%s => %s" % [ k, v ]
# }
