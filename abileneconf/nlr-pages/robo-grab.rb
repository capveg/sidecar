#!/usr/bin/ruby

require 'net/http'

srv = Net::HTTP.new('routerproxy.grnoc.iu.edu')

resp, toc = srv.get('/')

routers = Hash.new

# (toc.scan(/"http:\/\/routerproxy.grnoc.iu.edu\/([^"]+)"/) - [ 'nlr-packetnet/' ]).each { |site|
toc.scan(/"http:\/\/routerproxy.grnoc.iu.edu\/([^"]+)"/).each { |site|
# [ 'nlr-packetnet/' ].each { |site|
  puts "site: %s" % site
  resp2, middle = srv.get((site == 'nlr-packetnet/' ? '/%slgform.cgi' : '/%sproxy-controls.cgi' )% site)
  puts resp2.inspect
  middle.scan(/<option value='([^']+)'>/) { |router|
    routers[router] = site
    puts "  router: %s" % router
  }
  middle.scan(/<option value="([^"]+:ciscocrs)">/) { |router|
    routers[router] = site
    puts "  router: %s" % router
  }
  sleep 2
}

routers.each { |router,site|
  outputfile = 'Out=%s' % router
  puts "working on %s" % router
  if !Kernel::test(?e, outputfile) then
    begin
      resp = nil
      if site =~ /^nlr-packetnet/ then
        resp,data = srv.get('/%s/lg.cgi?router=%s&query=intv4&submit=Submit&command_args=' % [ site, router ])
      else
        resp,data = srv.get('/%s/proxy-output.cgi?router=%s&command=interface&submit=Execute&command_args=' % [ site, router ])
      end
      puts resp.inspect
      o = File.open(outputfile, 'w')
      o.write data
      o.close
      sleep 1
    rescue Timeout::Error
      puts "%s timed out" % router
    end
  else
    puts "skipping already downloaded %s" % router
  end
}


# nlr-packetnet
# chic.layer3.nlr.net:ciscocrs
# seat.layer3.nlr.net:ciscocrs
# wash.layer3.nlr.net:ciscocrs
# atla.layer3.nlr.net:ciscocrs
# denv.layer3.nlr.net:ciscocrs">denv.layer3.nlr.net</option>
# hous.layer3.nlr.net:ciscocrs">hous.layer3.nlr.net</option>
# losa.layer3.nlr.net:ciscocrs">losa.layer3.nlr.net</option>
# newy.layer3.nlr.net:ciscocrs">newy.layer3.nlr.net</option>
# resp,data = srv.get('/%s/proxy-output.cgi?router=%s&command=interface&submit=Execute&command_args=' % [ site, router ])
