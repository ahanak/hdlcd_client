$:.push File.join(File.dirname(__FILE__), 'lib')

require 'hdlcd_client'

HdlcdClient.open('/dev/ttyUSB0', 'localhost', 36962) do |dev|
  locked = false
  dev.each_packet do |packet|
    puts packet
  end
end