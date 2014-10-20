#!/usr/bin/ruby

require 'net/http'
require 'uri'

$just_do_one = false
$debug_http = true

srv = Net::HTTP.new('dooka.canet4.net')

resp, toc = srv.get('/lg/lg.php')

routers = toc.scan(/<option value ="(\d+\.\d+\.\d+\.\d+)">/)

puts routers.join("\n")

routers.each { |router|
  outputfile = 'Out=%s' % router
  puts "working on %s" % router
  if !Kernel::test(?e, outputfile) then
    begin
      srv.set_debug_output $stderr if($debug_http)

      url = URI.parse('http://dooka.canet4.net/lg/lg.php')
      req = Net::HTTP::Post.new(url.path)
      req.form_data = { "router" => router, "choice" => "show_interfaces", "IP" => "", "strCommand" => "",  "submitted" => "true", "submit" => "submit" }  # they escape the xml, making it not xml.
      res = srv.request(req)

      o = File.open(outputfile, 'w')
      o.write res.body
      o.close
      sleep 10
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
