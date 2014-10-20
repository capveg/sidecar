require 'progressbar'
require 'timeout'
require 'resolv'

class LambdaHash < Hash
  def initialize(b)
    @creator = b
  end
  def [](key)
    val = super(key)
    if(val==nil) then
      val = @creator.call(key)
      self[key]=val
    end
    val
  end
  def +(other) 
    # I think adding hashes should be as an open join.
    ret = LambdaHash.new(@creator)
    ( self.keys + other.keys ).each { |k|
      ret[k] = self[k] + other[k]
    }
    ret
  end
end

class LambdaArray < Array
  def initialize(b)
    @creator = b
  end
  def [](key)
    val = super(key)
    if(val==nil) then
      val = @creator.call(key)
      self[key]=val
    end
    val
  end
end

class Array
  private
  def iterate_progress_int(name) 
    pbar = FineProgressBar.new(name, self.length)
    pbar.set(0)
    r = yield self, pbar
    pbar.finish
    r
  end

  public
  def groupby(groupsize)
    (0..((self.length/groupsize).to_i)).map { |i|
      self[i*groupsize..((i+1)*groupsize-1)]
    }
  end
  def rle
    tmphash = LambdaHash.new( lambda { 0 } )
    self.each { |v| 
      tmphash[v] += 1
    }
    tmphash.sort # implicitly to_a.
  end
  def each_index_progress(name)
    pbar = FineProgressBar.new(name, self.length)
    pbar.set(0)
    r = (0..(self.length-1)).each { |i| yield i; pbar.inc }
    pbar.finish
    self
  end
  def each_with_index_progress(name)
    pbar = FineProgressBar.new(name, self.length)
    pbar.set(0)
    r = (0..(self.length-1)).each { |i| yield self[i], i; pbar.inc }
    pbar.finish
    self
  end
  def shuffle_progress!
    shuffle! # for now.
  end
  def shuffle!
    index = 0
    tmp = nil
    (size-1).downto(0) {|index|
      other_index = rand(index+1)
      next if index == other_index
      tmp = self[index]
      self[index] = self[other_index]
      self[other_index] = tmp
    }
    self
  end
  def quick_shuffle!(seconds, progress=true)
    # for when you want randomness, but aren't interested in waiting too long for it
    begin
      if(progress) then
        timeout(seconds) do 
          shuffle_progress!
        end
      else
        timeout(seconds) do 
          shuffle!
        end
      end
    rescue TimeoutError 
    end
    self
  end
  def each_progress(name)
    pbar = FineProgressBar.new(name, self.length)
    pbar.set(0)
    r = (0..(self.length-1)).each { |i| yield self[i]; pbar.inc }
    pbar.finish
    r
  end
  def delete_if_progress(name)
    pbar = FineProgressBar.new(name, self.length)
    pbar.set(0)
    r = self.delete_if { |v| pbar.inc; yield v }
    pbar.finish
    r
  end
  def inject(n)
    # apparently not needed in 1.8
    each { |value| n = yield(n, value) }
    n
  end
  def map_to_i
    map { |v| v.to_i }
  end
  def mean
    sum.to_f / length.to_f
  end
  def sum
    inject(0) { |n, value| n + value }
  end
  def product
    inject(1) { |n, value| n * value }
  end
  def max
    inject(0) { |n, value| ((n > value) ? n : value) }
  end
  def min
    if(self.length == 0) then 
      raise "Array min()'d is empty."
    end
    inject(self[0]) { |n, value| ((n < value) ? n : value) }
  end
  def <(x)
      (self <=> x) == -1
  end
  def median
    s = sort
    if (length > 0) then
      if (length % 2 == 0) then
        [s[length/2 - 1], s[length/2]].mean
      else
        s[(length-1)/2].to_f
      end
    else
      raise "median of empty list is undefined"
    end
  end
  def map_progress(name)
    if($stdout.isatty) then
      pbar = FineProgressBar.new(name, self.length)
      pbar.set(0)
      r = (0..(self.length-1)).map { |i| m = yield self[i]; pbar.inc; m }
      pbar.finish
      r
    else
      (0..(self.length-1)).map { |i| yield self[i]; }
    end
  end
  def each_inparallel_progress(nproc, name="", suppress_progressbar=false, batchsize=0)
    q = SizedQueue.new(nproc*2) # can prefetch 2x as many as consumed
    
    consumers = (1..nproc).map { |n| 
      t = Thread.new {
        Thread.current["index"] = n
        while( nextTask = q.shift ) do 
          yield nextTask
        end
      }
      Thread.pass # when we start up, try to get the thread running now.
      t
    } 

    batched = []
    if(suppress_progressbar) then
      each_progress(name) { |i| q.push(i) }
    else
      if(batchsize>0) then
        each { |i| 
          batched.push(i) 
          if(batched.length >= batchsize)  then
            q.push(batched)
            batched = []
          end
        }
        if(batched.length > 0) then 
          q.push(batched)
        end
      else
        each { |i| q.push(i) }
      end
    end

    # have them break from the while loop.
    consumers.map { |thr| q.push(nil) }

    # and reap the threads.
    consumers.map { |thr| thr.join }

    self
  end
end

class Hash
  def inject(n)
    each { |value| n = yield(n, value) }
    n
  end
  def key_for_max_val
    v = 0; k = nil
    each { |key, value| k,v = if(v > value) then [k,v] else [key,value] end }
    k
  end
  def sort_descending_value
    sort { |a,b| b[1] <=> a[1] }
  end
  def each_progress(name)
    pbar = FineProgressBar.new(name, self.length)
    pbar.set(0)
    r = self.each { |k,v| yield k,v ; pbar.inc }
    pbar.finish
    r
  end
end

# under devel
class File
  def each_progress(name)
    pbar = FineProgressBar.new(name, self.stat.size)
    pbar.set(0)
    while ( (ln = self.gets) ) do
      yield ln
      pbar.set(self.pos)
    end
    pbar.finish
    self
  end
end

class FineProgressBar < ProgressBar

  def initialize(label, len)
    @prev_percentage = -1
    @last_time = 0
    super(label, len)
  end

  # def bar(percentage)
    # len = percentage * @bar_length / 100
    # sprintf("|%s%s|", @bar_mark * len, " " *  (@bar_length - len))
  # end
  # def show 
  #  @out.printf("%s %5.1f%% %s %s %s", 
#		@title + ":", 
#                percentage, 
#                bar(percentage),
#                eta,
#                eol)
#  end

  def show_progress
    #if(@prev_percentage == nil) then 
      # @prev_percentage = -1
      # @last_time = 0
    #end
    if @total.zero?
      cur_percentage = 100
    else
      cur_percentage  = (@current * 1000 / @total).to_i.to_f / 10.0
    end

    this_time = Time.now
    
    if ( cur_percentage > @prev_percentage && (this_time.to_f > @last_time.to_f + 1)) || @is_finished
      show
      @prev_percentage = cur_percentage
      @last_time = this_time
    end
  end
    
end

begin 
require 'postgres'
def insertIPname(addr) 
  if($ps == nil) then
    $ps = PGconn.connect('jimbo', nil, nil, nil, 'policy')
    if($ps == nil) then
      raise "couldn't connect to db"
    end
  end
  name = begin 
           Resolv.getname(addr)
         rescue
           addr
         end
  # puts [ name, addr ].join(' ')
  $stderr.print "x\r"
  res = $ps.exec("insert into skIP2name (ip, name) values ('#{addr}', '#{name}')");
  if( res.status != PGresult::COMMAND_OK ) 
    raise "insert failed #{res.status}."
  end
end

$nameCache = Hash.new
$ps = nil

def getNameFromCache(ip) 
  if($nameCache.has_key?(ip)) then
    return $nameCache[ip]
  end
  if($ps == nil) then
    $ps = PGconn.connect('jimbo', nil, nil, nil, 'policy')
    if($ps == nil) then
      raise "couldn't connect to db"
    end
  end
  $nameCache[ip] = if(ip =~ /^10\./) then
                     ip 
                   else
                     n = queryIP(ip)
                     if(n == "as.yet.unknown") then
                       insertIPname(ip)
                       n = queryIP(ip)
                     end
                     n
                   end
  return $nameCache[ip] # redundant return.
end

rescue LoadError
# don't really need postgres sometimes.
end
