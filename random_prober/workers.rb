# workers is a stupid^H^H^H^H^Hsimple thread safe construct to flag and test
# 	how many threads could potentially produce more work


class Workers
	def initialize(size)
		@workerList=Array.new(size,0)
		@nWorking=0
		@lock= Mutex.new
	end
	def startWorking(worker)
		@lock.synchronize {
			raise "Bad worker id #{worker.to_s}" unless worker.is_a?(Integer)
			raise "Bad worker id #{worker.to_s}" if worker >= @workerList.length
			if @workerList[worker]==0
				@nWorking+=1
			end
			@workerList[worker]=1
		}
	end
	def stopWorking(worker)
		@lock.synchronize {
			raise "Bad worker id #{worker.to_s}" unless worker.is_a?(Integer)
			raise "Bad worker id #{worker.to_s}" if worker >= @workerList.length
			if @workerList[worker]==1
				@nWorking-=1
				@workerList[worker]=0
			end
			raise "Worker's List is screwed" if @nWorking<0
		}
	end
	def nWorking?
		@lock.synchronize {
			@nWorking
		}
	end
	def nWorkers?
		@lock.synchronize {
			@nWorking
		}
	end
	def inProgress?
		@lock.synchronize {
			return @nWorking>0
		}
	end
end




