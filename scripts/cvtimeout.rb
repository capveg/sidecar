#!/usr/bin/ruby

#require 'timeout'


module Timeout

  ##
  # Raised by Timeout#timeout when the block times out.

  class Error<Interrupt
  end

  ##
  # Executes the method's block. If the block execution terminates before +sec+
  # seconds has passed, it returns true. If not, it terminates the execution
  # and raises +exception+ (which defaults to Timeout::Error).
  #
  # Note that this is both a method of module Timeout, so you can 'include
  # Timeout' into your classes so they have a #timeout method, as well as a
  # module method, so you can call it directly as Timeout.timeout().

  def timeout(sec, exception=Error)
    return yield if sec == nil or sec.zero?
    raise ThreadError, "timeout within critical session" if Thread.critical
    begin
      x = Thread.current
      y = Thread.start {
        sleep sec
        x.raise exception, "execution expired" if x.alive?
      }
      yield sec
      #    return true
    ensure
      y.kill if y and y.alive?
    end
  end

  module_function :timeout

end

def timeout(n, e=Timeout::Error, &block) # :nodoc:
  Timeout::timeout(n, e, &block)
end

##
# Another name for Timeout::Error, defined for backwards compatibility with
# earlier versions of timeout.rb.

#TimeoutError = Timeout::Error # :nodoc:

# because ruby's timeout.rb does not kill a process when it timesout
module Kernel
	def system_with_timeout(timeout,*sysargs)
		if (pid = Kernel.fork) != nil		
			begin	# parent
				timeout(timeout) {
					Process.waitpid(pid,0)
#					$stderr.puts "Process success"
					pid=-1	# tell the exit code that the process finished
				}
			ensure 
				if pid != -1 
#					$stderr.puts "Process timeout: killing #{pid}"
					Process.kill("TERM",pid) 
				end
			end
		else	# child
			Kernel.exec(*sysargs)
			raise "Should never get here either"
		end
	end
end

if $0 == __FILE__
	
	$stderr.puts "Test without timeout"
	Kernel.system_with_timeout(2,"sleep 1")
	begin
		$stderr.puts "Test with timeout"
		Kernel.system_with_timeout(2,"sleep 10000")
		raise  "		Error! should never have gotten here"
		rescue Timeout::Error 
			$stderr.puts "Correctly caught timeout"
	end

end
