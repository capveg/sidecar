#!/usr/bin/ruby1.8

require "progressbar"
require "thread"

module ProgressBar_Mixin
  def each_index_progress(name="") 
    pbar = ProgressBar.new(name, length)
    pbar.set(0)
    r = each_index { |i| yield i; pbar.inc }
    pbar.finish
    r
  end
  def each_with_index_progress(name="") 
    pbar = ProgressBar.new(name, length)
    pbar.set(0)
    r = each_with_index { |v,i| yield v,i; pbar.inc }
    pbar.finish
    r
  end
  def each_progress(name="") 
    pbar = ProgressBar.new(name, length)
    pbar.set(0)
    r = each { |i| yield i; 
      begin
        if self.respond_to?(:tell) then 
          pbar.set(self.tell) 
        else 
          pbar.inc 
        end 
      rescue => e
        # swallow, it's just the progress bar after all
      end
    }
    pbar.finish
    r
  end
  def map_progress(name="") 
    pbar = ProgressBar.new(name, length)
    pbar.set(0)
    r = map { |i| e = yield i; if self.respond_to?(:tell) then pbar.set(self.tell) else pbar.inc end; e }
    pbar.finish
    r
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

if __FILE__ == $0
  require 'test/unit'
  class Array 
    include  ProgressBar_Mixin
  end

  class ProgTest < Test::Unit::TestCase
    def test_eachp
      [ 1, 2, 3, 4 ].each_inparallel_progress(4, "array", false, 3) { |i| puts i.inspect + i.map { |j| j.inspect }.join(" "); sleep(1) }
      [ 1, 2, 3, 4 ].each_inparallel_progress(4, "array", false, 2) { |i| puts i.inspect + i.map { |j| j.inspect }.join(" "); sleep(1) }
      [ 1, 2, 3, 4 ].each_inparallel_progress(4, "array", false, 0) { |i| puts i.inspect; sleep(1) }
      [ 1, 2, 3, 4 ].each_inparallel_progress(4, "array") { |i| sleep(1) }
      [ 1, 2, 3, 4 ].each_progress("array") { |i| sleep(1) }
    end
  end
end

class IO
  include ProgressBar_Mixin
  def length
    stat.size
  end
end

class Array
  include ProgressBar_Mixin
end
