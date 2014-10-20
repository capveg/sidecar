#!/usr/bin/ruby

require 'net/http'
require 'uri'

$just_do_one = false
$debug_http = false

srv = Net::HTTP.new('stats.geant2.net')

resp, toc = srv.get('/lg/')

routers = toc.scan(/<option id="(\w\w\d\.\w+\.\w+\.geant2\.net)"\W/)

puts routers.join("\n")

routers.each { |router|
  outputfile = 'Out=%s' % router
  puts "working on %s" % router
  if !Kernel::test(?e, outputfile) then
    begin
      srv.set_debug_output $stderr if($debug_http)

      url = URI.parse('http://stats.geant2.net/lg/process.jsp')
      req = Net::HTTP::Post.new(url.path)
      req.form_data = { "routers" => router, "commands" => "Show Interface", "args" => "", "submit" => "Submit" }  # they escape the xml, making it not xml.
      res = srv.request(req)

      puts "the session cookie is: %s" % res['Set-Cookie']

      sleep 18

      url = URI.parse('http://stats.geant2.net/lg/result.jsp')
      req = Net::HTTP::Get.new(url.path)
      # req.form_data = { "routers" => router, "commands" => "Show Interface", "args" => "", "submit" => "Submit", "xml" => "" }
      req['Cookie'] = res['Set-Cookie']
      res = srv.request(req)

      o = File.open(outputfile, 'w')
      o.write res.body
      o.close
      sleep 1
    rescue Timeout::Error
      puts "%s timed out" % router
    end
    exit if($just_do_one)
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
