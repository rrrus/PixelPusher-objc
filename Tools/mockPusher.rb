#!/usr/bin/env ruby

require 'socket'
require 'optparse'
require 'yaml'

# typedef enum {
# 	ETHERDREAM = 0,
# 	LUMIABRIDGE = 1,
# 	PIXELPUSHER = 2 }
# DeviceType;

# typedef struct DiscoveryPacketHeader {
# 	uint8_t mac_address[6];
# 	uint8_t ip_address[4];  // network byte order
# 	uint8_t device_type;
# 	uint8_t protocol_version; // for the device, not the discovery
# 	uint16_t vendor_id;
# 	uint16_t product_id;
# 	uint16_t hw_revision;
# 	uint16_t sw_revision;
# 	uint32_t link_speed;    // in bits per second
# } DiscoveryPacketHeader;

# typedef struct PixelPusher {
# 	uint8_t  strips_attached;
# 	uint8_t  max_strips_per_packet;
# 	uint16_t pixels_per_strip;  // uint16_t used to make alignment work
# 	uint32_t update_period; // in microseconds
# 	uint32_t power_total;   // in PWM units
# 	uint32_t delta_sequence;  // difference between received and expected sequence numbers
# 	int32_t controller_ordinal; // ordering number for this controller.
# 	int32_t group_ordinal;      // group number for this controller.
# 	uint16_t artnet_universe;   // configured artnet starting point for this controller
# 	uint16_t artnet_channel;
# 	uint16_t my_port;
# 	uint8_t strip_flags[8];     // flags for each strip, for up to eight strips;
# 										// if more than eight strips are supported, this is longer but never shorter than 8 bytes
# 	uint32_t pusher_flags;      // flags for the whole pusher
# 	uint32_t segments;          // number of segments in each strip
# 	uint32_t power_domain;      // power domain of this pusher
# } PixelPusher;

DiscoveryPort = 7331

# device types
ETHERDREAM = 0
LUMIABRIDGE = 1
PIXELPUSHER = 2

options = {
	:number => 0,
	:group => 0,
	:strips_attached => 8,
	:pixels_per_strip => 240,
}
OptionParser.new do |opts|
	opts.banner = "Usage: mockPusher.rb [options]"

	opts.on("-n", "--number N", Integer, "controller number") do |v|
		options[:number] = v
	end
	opts.on("-g", "--group N", Integer, "controller group") do |v|
		options[:group] = v
	end
	opts.on("-s", "--strips N", Integer, "number of strips") do |v|
		options[:strips_attached] = v
	end
	opts.on("-p", "--pixels N", Integer, "pixels per strip") do |v|
		options[:pixels_per_strip] = v
	end
	opts.on("-f", "--config FILENAME", "path to yaml file containing multiple pusher configs") do |v|
		options[:configFile] = v
	end
	# TODO:
	# 	- MAC addr
	# 	- malformed packets (header, pixelPusher)
	# 	- update period variance
	# 	- power variance
end.parse!

$lastMAC = 1
$lastPort = 64203
def makePusher(options)
	ipaddr = Socket::getaddrinfo(Socket.gethostname,"echo",Socket::AF_INET)[0][3]
		.split(".")
		.map { |e| e.to_i }

	pusher = options.merge({
		:mac => [0xff,0xff,0xff,0xff,0xff, $lastMAC],
		:ipaddr => ipaddr,
		:port => $lastPort,
	})
	$lastMAC += 1
	$lastPort += 1

	### Discovery packet header
	# MAC addr
	data = pusher[:mac].pack("CCCCCC")
	# IP addr
	data += pusher[:ipaddr].pack("CCCC")
	# device type, protocol_version, vendor_id, product_id
	data += [PIXELPUSHER, 2, 12, 2].pack("CCvv")
	# hw_revision, sw_revision, link_speed
	data += [4, 121, 100000000].pack("vvV")

	### PixelPusher packet header
	# strips attached, max_strips_per_packet, pixels_per_strip, update_period, power_total, delta_sequence
	data += [pusher[:strips_attached], 2, pusher[:pixels_per_strip], 3000000, 12000, 0].pack("CCvVVV")
	# controller_ordinal, group_ordinal, artnet_universe, artnet_channel
	data += [pusher[:number], pusher[:group], 0, 0].pack("VVvv")
	# my_port, strip_flags (8 strip flags plus 2 padding bytes)
	data += [pusher[:port], 0,0,0,0,0,0,0,0,0,0].pack("vC10")
	# pusher_flags, segments, power_domain
	data += [0, 0, 0].pack("VVV")

	# DEBUG:
	# idx = 1
	# data.unpack("C*").each { |e|
	# 	print("%02x" % e)
	# 	if (idx % 8 == 0)
	# 		print(" ")
	# 	end
	# 	if (idx % 64 == 0)
	# 		print("\n")
	# 	end
	# 	idx += 1
	# }
	# puts

	pusher[:discoveryPacket] = data

	s = UDPSocket.new
	s.bind(pusher[:ipaddr].map { |e| e.to_s }.join("."), pusher[:port])
	pusher[:listener] = s

	return pusher
end

Pushers = []
if (options[:configFile])
	configs = YAML::load_file(options[:configFile])
	if (!configs.kind_of?(Array))
		puts("invalid config file")
	else
		configs.each do |config|
			# merge the config on top of our default options
			anOpt = options.merge(config)
			Pushers.push(makePusher(anOpt))
		end
	end
else
	Pushers.push(makePusher(options))
end

if (Pushers.length > 0)
	addr = ['<broadcast>', DiscoveryPort] # broadcast address
	UDPSock = UDPSocket.new
	UDPSock.setsockopt(Socket::SOL_SOCKET, Socket::SO_BROADCAST, true)

	loop do
		Pushers.each do |pusher|
			UDPSock.send(pusher[:discoveryPacket], 0, addr[0], addr[1])
			begin
				stuff = pusher[:listener].recvfrom_nonblock(1500)
				if (stuff)
					puts("data for pusher %s" % pusher[:mac].map { |e| e.to_s }.join(":"))
				end
			rescue Exception
			end
		end
		sleep(1)
	end

	UDPSock.close
end
