require "hdlcd_client/version"
require "thread"
require "socket"


# The HdlcClient client module is the namespace for the classes of the HDLCd client.
# The class {HdlcDevice} implements a high-level client that is easy to use and should be sufficent for most applications.
#
# If you need more control for special use cases, the other classes in the {HdlcdClient} module can be used directly.
#
# @example reading the payload delivered through hdlc
#   HdlcdClient.open('/dev/ttyUSB0') do |dev|
#     dev.each_packet do |packet|
#       puts packet # human friendly output
#       payload = packet.payload # do something with it
#     end
#   end
#
# @example locking, releasing, and query port status
#   HdlcdClient.open('/dev/ttyUSB0') do |dev|
#     dev.lock
#     sleep 10 # do something different with the port
#     dev.release
#     sleep 1
#     puts dev.port_status.inspect
#   end
#
# @example monitor the port status
#   HdlcdClient.open('/dev/ttyUSB0') do |dev|
#     dev.port_status_changed do |new_port_status|
#       puts new_port_status.inspect
#     end
#   end
#
module HdlcdClient

  # The tcp port to connect to if none is given.
  DEFAULT_PORT = 36962

  # The host to connect to if none is given.
  DEFAULT_HOST = 'localhost'

  # Create a new {HdlcDevice} and pass it to the given block.
  #
  # Using this method should be preferred compared to the usage of {HdlcDevice#initialize},
  # because all ressources will be cleaned up properly after exiting the block even if an exception occures.
  #
  # @example open a connection
  #   HdlcdClient.open('/dev/ttyUSB0') do |device|
  #     # Do something with device
  #     raise 'An error' # even this is save
  #   end
  #   # all connections are closed now
  #
  # @param [String] serial_port_name is the device path under linux or the name of the COM-Port under windows
  # @param [String] host is the hostname of the computer where the HDLCd runs on.
  # @param [Fixnum] tcp_port is the TCP port number used by the HDLCd server.
  # @yield [hdlc_device] Passs the device to the block.
  def self.open(serial_port_name, host = DEFAULT_HOST, tcp_port = DEFAULT_PORT, options = {})
    #TODO: what about serial_port_name on windows?
    d = HdlcDevice.new(serial_port_name, host, tcp_port, options)
    begin
      yield(d)
    ensure
      d.close
    end
  end

  # This class is a highlevel client for the HDLCd.
  # The class might open multiple TCP connections to the HDLCd for data and control message exchange.
  class HdlcDevice

    # Create a new HdlcDevice object which can be used to interact with an device speaking HDLC.
    # @param [String] serial_port_name is the device path under linux or the name of the COM-Port under windows
    # @param [String] host is the hostname of the computer where the HDLCd runs on.
    # @param [Fixnum] tcp_port is the TCP port number used by the HDLCd server.
    # @return [HdlcDevice] the created device.
    def initialize(serial_port_name, host = DEFAULT_HOST, tcp_port = DEFAULT_PORT, options)
      #TODO: options parameter
      @host = host
      @tcp_port = tcp_port
      @serial_port_name = serial_port_name
      @port_status = {}
      @port_status_lock = Mutex.new
    end

    # Lock the serial port in order to use it directly through the operating system methods.
    # This signals towards the HDLCd, that you want to use the port exclusively.
    # This call results in HDLCd closing the device.
    # No messages will be transferred anymore to any client listening to that serial port via HDLCd.
    def lock
      control_connection.write ControlPacket.new(:lock).serialize
    end

    # This signals, that the port is not longer exclusively reqired and can be opened by the HDLCd again.
    # After a release, the delivery of the HDLC payloads will continue as normal.
    def release
      control_connection.write ControlPacket.new(:release).serialize
    end

    # This method can be used to subscribe to data packets delivered by the HDLCd.
    # Use this method if you want to receive the data sent over HDLC.
    # @yield [packet] Passes packages containing data ({DataPacket}) to the block as they arrive.
    def each_data_packet
      DataPacket.each(data_connection) {|packet| yield(packet)}
    end

    # This method can be used to subscribe to control packets delivered by the HDLCd
    # through the secondary control connection.
    # @yield [packet] Passes packages containing control information ({ControlPacket}) to the block as they arrive.
    def each_control_packet
      ControlPacket.each(control_connection(true)) {|packet| yield(packet)}
    end

    # This method passes all packets (data and control) from the data connection to the block.
    #
    # The control connection is not evaluated here.
    # @yield [packet] Passes packages containing control information or data (any subclass of {Packet}) to the block as they arrive.
    def each_packet
      Packet.each(data_connection) {|packet| yield(packet)}
    end

    # This method can be used to subscribe to port status changes.
    # The method uses the control connection to detect port changes and calls the block each time the status changes.
    # @yield [port_state] Pases the new port state as {Hash} to the block when it changes.
    def port_status_changed
      cur_port_status = {}
      each_control_packet do |packet|
        if packet.command == :port_status
          new_port_status = packet.information
          if cur_port_status != new_port_status
            yield(new_port_status.clone)
            cur_port_status = new_port_status
          end
        end

      end
    end

    # This is the polling alternative to {#port_status_changed}.
    # @return [Hash] the last known port status.
    def port_status
      status = nil
      @port_status_lock.synchronize {
        status = @port_status.clone
      }
      return status
    end

    # Closes all TCP connections and stop worker thread()s).
    def close
      @data_socket.close if @data_socket
      @control_socket.close if @control_socket
      @thread.kill if @thread
      @thread = nil
    end

    private

    # Creates a new data connection or returns the already opened.
    # @return [TCPSocket] an already opened and initialized tcp socket that is used to deliver data.
    def data_connection
      if @data_socket.nil?
        @data_socket = TCPSocket.new @host, @tcp_port
        session_header = SessionHeaderMessage.new(@serial_port_name)
        @data_socket.write session_header.serialize
      end
      return @data_socket
    end

    # Creates a new control connection or returns the already opened.
    # @param [true, false] read is true if the connection should be used to read control data.
    # @return [TCPSocket] an already opened and initialized tcp socket that is used to deliver control messages.
    def control_connection(read = false)
      if @control_socket.nil?
        @control_socket = TCPSocket.new @host, @tcp_port
        session_header = SessionHeaderMessage.new(@serial_port_name, :type_of_data => :port_status_only, :rx_data => false)
        @control_socket.write session_header.serialize

        # Start a parsing thread if no read is requered to feth the data from socket
        parse_port_status unless read

      elsif @thread and read
        # stop the parsing thread as reading is requested now
        @thread.kill
        @thread = nil
      end

      return @control_socket
    end

    # Starts a background job, which reads all incoming data from the control socket (important).
    def parse_port_status
      @thread = Thread.new(@control_socket) do |socket|
        ControlPacket.each(socket) do |packet|
          if packet.command == :port_status
            @port_status_lock.synchronize {
              @port_status = packet.information
            }
          end
        end
      end
    end
  end

  # This class represents the session header message
  # which must be sent only once directly after the TCP connection is initialized.
  class SessionHeaderMessage
    TYPE_OF_DATA = {
        :payload => 0,
        :port_status_only => 1,
        :payload_raw => 2,
        :hdlc_raw => 3,
        :hdlc_dissected => 4
    }.freeze

    # The protocol version we speak
    VERSION = 0

    # The options, that are taken as defaults.
    # @see #initialize
    DEFAULT_OPTIONS = {
        :version => VERSION,
        :type_of_data => :payload,
        :invalids => false,
        :tx_data => false,
        :rx_data => true
    }

    # Create a new session header message.
    # @param [String] serial_port_name is the name of the serial port to access.
    # @param [Hash] options are a hash of options overwriting the default message options.
    #   Valid keys are those that exist in {DEFAULT_OPTIONS}.
    def initialize(serial_port_name, options = {})
      default_options = DEFAULT_OPTIONS.clone
      @serial_port_name = serial_port_name
      @options = default_options.merge(options)
    end

    # Serialize the message to a binary string.
    # @example initialize a default data channel
    #   s = TCPSocket.new('localhost', 36962)
    #   s.write  SessionHeaderMessage.new('/dev/ttyUSB0').serialize
    #
    # @return [String] binary data packet into a string.
    def serialize
      # build service access point specifier
      sap = 0
      sap |= 0b0001 if @options[:rx_data]
      sap |= 0b0010 if @options[:tx_data]
      sap |= 0b0100 if @options[:invalids]

      # add the upper nibble
      sap |= (TYPE_OF_DATA[@options[:type_of_data]].to_i << 4)

      return [@options[:version], sap, @serial_port_name.length].pack('CCC') + @serial_port_name
    end
  end

  # Packets are messages sent from the hdlcd.
  # These can either be control packets or data packets containing a payload.
  # This class is used to parse the tcp stream coming from the hdlcd.
  class Packet
    @@types = {}

    attr_accessor :content_id, :reliable
    attr_reader :invalid, :was_sent

    def contains_data?
      false
    end

    def initialize(content_id = 0, reliable = true)
      @content_id = content_id
      @reliable = reliable
      @invalid = false
      @was_sent = false
    end

    def invalid?
      self.invalid ? true : false
    end

    def valid?
      !self.invalid?
    end

    def reliable?
      self.reliable ? true : false
    end

    def was_sent?
      self.was_sent ? true : false
    end

    def serialize
      #TODO: implement serialization
      raise NotImplementedError, "This class does not (yet) support serialization"
    end

    def self.deserialize(io)
      # Type field:
      # Bits 7..4: content_id (upper nibble)
      # Bit 2: reliable flag (1 if message was or should be transmitted reliable via hdlc)
      # Bit 1: invalid flag (1 if the packet is damaged)
      # Bit 0: was_sent flag (1 if this is a message transmitted to the serial device, must be 0 for messages to be transmitted)

      type_field = io.readbyte

      # the upper nibble is the content_id
      content_id = type_field >> 4

      # bit 2 is reliable flag
      reliable = (type_field & 0x4) > 0

      # bit 1 is invalid flag
      invalid = (type_field & 0x2) > 0

      # bit 0 is was_sent flag
      was_sent = (type_field & 0x1) > 0

      # Now parse the following byte(s) by the class registered for the current content_id
      object = nil
      if @@types.has_key? content_id
        # call the deserilize method of the child class for the given content_id
        object = @@types[content_id].deserialize(io)
      else
        # there is no child class for this specific content id. Return an abstract Packet
        # Warning: this will only work if there are no further bytes in the packet
        #puts "Warning: content_id #{content_id} not found in #{@@types.inspect}"
        object = Packet.new()
      end

      object.set_fields(content_id, reliable, invalid, was_sent)
      return object
    end

    def self.each(io)
      loop do
        packet = Packet.deserialize(io)
        # Packet.deserialize returns a Packet or a doughter class of Packet
        # As the method can inhererited, i.e. called as "DataPacket.each", the the "if is_a? self" statement ensures that only DataPackets are given to the block and other Packets are ignored.
        yield(packet) if packet.is_a? self
      end
    end

    def set_fields(content_id, reliable, invalid, was_sent)
      @content_id = content_id
      @reliable = reliable
      @invalid = invalid
      @was_sent = was_sent
    end

    def to_s
      s = (was_sent? ? '<- ' : '-> ')
      s += self.class.to_s.gsub(/^.*::/, '')
      s += ' ['
      s += [
          (reliable? ? 'reliable' : 'unreliable'),
          (valid? ? 'valid' : 'invalid')
      ].join(',')
      s+= ']'
      return s
    end

    protected

    def type_field
      field = @content_id << 4
      field |= 0x4 if reliable?
      field |= 0x2 if invalid?
      field |= 0x1 if was_sent?
      return field
    end

    def self.register_type(content_id, packet_class)
      @@types[content_id] = packet_class
    end
  end

  class ControlPacket < Packet
    CONTENT_ID = 1
    register_type(CONTENT_ID, self)

    attr_reader :information, :command

    COMMANDS = {
        :lock => 0x01,
        :release => 0x00,
        :echo => 0x10,
        :keep_alive => 0x20,
        :port_kill_request => 0x30
    }.freeze

    INDICATIONS_CONFIRMATIONS = {
        :port_status => 0x00,
        :echo => 0x10,
        :keep_alive => 0x20
    }.freeze

    def initialize(command = :release, information = {})
      # control packets always have all flags as zeros
      super(CONTENT_ID, 0)
      raise ArgumentError, "Invalid Command: #{command.inspect}" unless COMMANDS.has_key? command
      @command = command
      @information = information
    end

    def serialize
      [type_field, COMMANDS[@command]].pack('CC')
    end

    def self.deserialize(io)
      data = io.readbyte
      command = INDICATIONS_CONFIRMATIONS.invert[data & 0xF0]
      information = {}
      if command == :port_status
        information[:alive] = (data & 0x04) > 0
        information[:locked_by_others] = (data & 0x02) > 0
        information[:locked_by_me] = (data & 0x01) > 0
      end
      packet = ControlPacket.new
      packet.set_control_fields(command, information)
      return packet
    end

    def set_control_fields(command, information)
      @command = command
      @information = information
    end

    def to_s
      super + ' ' + @command.to_s + ' ' + @information.inspect
    end

  end

  class DataPacket < Packet
    CONTENT_ID = 0
    register_type(CONTENT_ID, self)

    attr_accessor :payload

    def initialize(payload, reliable = true)
      super(CONTENT_ID, reliable)
      @payload = payload
    end

    # Overwritten from Packet.
    def contains_data?
      payload and payload.length > 0
    end


    def self.deserialize(io)
      # first two bytes are the length
      # given as 16-bit unsigned integer in network byte order (Directive 'n')
      length_raw = io.read(2)
      length = length_raw.unpack('n').first
      unless length_raw and length_raw.length == 2
        raise EOFError, "Unexpected EOF while trying to read DataPacket length."
      end

      payload = io.read(length)
      unless payload and payload.length == length
        raise EOFError, "Unexpected EOF while trying to read DataPacket payload."
      end
      return DataPacket.new(payload)
    end

    def to_s
      super + ' ' + Helper.binary_data_as_hex(payload)
    end
  end

  private

  module Helper
    def self.binary_data_as_hex(binary)
      binary.unpack('C' * binary.length).collect{|byte| '%02X' % byte}.join(' ')
    end
  end

end
