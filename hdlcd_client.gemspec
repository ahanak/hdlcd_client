# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'hdlcd_client/version'

Gem::Specification.new do |spec|
  spec.name          = "hdlcd_client"
  spec.version       = HdlcdClient::VERSION
  spec.authors       = ["André Hanak"]
  spec.email         = ["impressum@a-hanak.de"]
  spec.summary       = %q{This is a client for the HDLCd to access serial devices over HDLC. }
  spec.description   = %q{You can find the HDLCd here: https://github.com/Strunzdesign/hdlc-tools}
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.7"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec"
end
