
require 'thread'

class Queue
	# Grab at least 1, but up to n objects from the queue without blocking
	#	if the queue is currently empty, block until there is at least 1 object
	public
	def pop_upto_n(n)
		arr = Array.new
		while true
			n.times {
				begin
					arr << pop(true)	# non-blocking
					rescue ThreadError => e 
						break unless arr.empty?	# break if we have something
						arr << self.pop	# blocking
				end
			}
			break unless arr.empty?
		end
		arr
	end
 	# `ruby -r capveg-utils.rb -e 'Queue.test_pop_upto_n'`  to test
	def Queue.test_pop_upto_n
		q = Queue.new
		5.times { |i| q.push(i)}
		thread = Thread.new {
			puts "Fetching..."
			a = q.pop_upto_n(3)
			puts "Got #{a.size} elements back"
			puts "Fetching..."
			a = q.pop_upto_n(5)
			puts "Got #{a.size} elements back"
			puts "Fetching..."
			a = q.pop_upto_n(5)
			puts "Got #{a.size} elements back"
		}
		puts "Sleeping... "
		sleep(2)
		q.push(10)
		thread.join
	end
	def unshift(obj)
		Thread.critical = true
		@que.unshift obj
		begin
			t = @waiting.shift
			t.wakeup if t
		rescue ThreadError
				retry
		ensure
			Thread.critical = false
		end
		begin
			t.run if t
		rescue ThreadError
		end
	end

end

