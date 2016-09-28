$:.push File.join(File.dirname(__FILE__), '../lib')

require 'hdlcd_client'

port = (ARGV.first or '/dev/ttyUSB0')

HdlcdClient.open(port) do |device|
  device.each_packet do |packet|
    puts packet
  end
end