require "hdlcd_client/version"

module HdlcdClient

  def self.open(serial_port_name, host, port, options = {})

  end

  class ConnectionController
    def lock

    end

    def release

    end

    def each_data_packet

    end

    def each_control_packet

    end


  end

  class Connection
    def initialize(host, port)

    end

  end



  class SessionHeaderMessage
    TYPE_OF_DATA = {
        :payload => 0,
        :port_status_only => 1,
        :payload_raw => 2,
        :hdlc_raw => 3,
        :hdlc_dissected => 4
    }.freeze

    VERSION = 0

    def initialize(serial_port_name, options = {})
      default_options = {
          :version => VERSION,
          :type_of_data => :payload,
          :invalids => false,
          :tx_data => false,
          :rx_data => true
      }
      @serial_port_name = serial_port_name
      @options = default_options.merge(options)
    end


    def serialize
      # build service access point specifier
      sap = 0
      sap |= 0b0001 if @options[:rx_data]
      sap |= 0b0010 if @options[:tx_data]
      sap |= 0b0100 if @options[:invalids]

      # add the upper nibble
      sap |= (TYPE_OF_DATA[@options[:type_of_data]].to_i << 4)

      return [@options[:version], sap, serial_port_name.length].pack('CCC') + @serial_port_name
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

    protected

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
  end

end
