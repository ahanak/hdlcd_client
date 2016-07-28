require 'rspec'
require 'hdlcd_client'

describe 'Correct Parsing of messages' do
  let(:empty_data) { [0x00, 0x00, 0x00].pack('CCC') }
  let(:reliable_data) { [0x04, 0x00, 0x03, 0x01, 0x02, 0x03].pack('CCCCCC') }
  let(:port_status_locked) { [0x10, 0x05].pack('CC') }


  it 'should deserialize an empty not reliable data packet correctly' do
    packet = HdlcdClient::Packet.deserialize(StringIO.new(empty_data))
    expect(packet).to be_a HdlcdClient::DataPacket
    expect(packet.reliable?).to be false
    expect(packet.valid?).to be true
    expect(packet.contains_data?).to be false
  end

  it 'should deserialize a reliable data packet correctly' do
    packet = HdlcdClient::Packet.deserialize(StringIO.new(reliable_data))
    expect(packet).to be_a HdlcdClient::DataPacket
    expect(packet.reliable?).to be true
    expect(packet.valid?).to be true
    expect(packet.contains_data?).to be true
  end

  it 'should deserialize a port status control packet correctly' do
    packet = HdlcdClient::Packet.deserialize(StringIO.new(port_status_locked))
    expect(packet).to be_a HdlcdClient::ControlPacket
    expect(packet.reliable?).to be false
    expect(packet.valid?).to be true
    expect(packet.contains_data?).to be false
    expect(packet.command).to be :port_status
    expect(packet.information).to be_a Hash
    expect(packet.information[:alive]).to be true
    expect(packet.information[:locked_by_others]).to be false
    expect(packet.information[:locked_by_me]).to be true
  end
end