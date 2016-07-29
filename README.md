# HdlcdClient

Still at beginning of the Work. Currently not usable
TODO: Write a gem description

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'hdlcd_client'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install hdlcd_client

## Usage

The library is written with the goal to provide an easy interface to an already running HDLCd.
The following examples show simple code for some common use-cases.

### Reading the payload delivered through HDLC

    HdlcdClient.open('/dev/ttyUSB0') do |dev|
        dev.each_packet do |packet|
            puts packet # human friendly output
            payload = packet.payload # do something with it
        end
    end

### Lock, release, and query port status

    HdlcdClient.open('/dev/ttyUSB0') do |dev|
        dev.lock
        sleep 10 # do something different with the port
        dev.release
        sleep 1
        puts dev.port_status.inspect
    end

### Monitor the port status

    HdlcdClient.open('/dev/ttyUSB0') do |dev|
        dev.port_status_changed do |new_port_status|
            puts new_port_status.inspect
        end
    end


See {HdlcdClient} module description and take a look at the classes for tips for more advantage usage.


## Dokumentation / Reference

See http://www.rubydoc.info/github/ahanak/hdlcd_client/master


## Contributing and Development info

### Running Tests

    $ rake spec

### Contributing

1. Fork it ( https://github.com/ahanak/hdlcd_client/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
