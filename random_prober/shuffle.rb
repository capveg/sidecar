
require 'cvtimeout'
require 'progressbar_mixin'


class Array
  include ProgressBar_Mixin
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
end
