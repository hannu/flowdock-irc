require 'rubygems' if RUBY_VERSION < '1.9'
require 'eventmachine'
require 'em-http'
require 'em-eventsource'
require 'net/http'
require 'net/https'
require 'json'
require 'isaac/bot'

PERSONAL_TOKEN = ""
FLOW = "api-test"
ORGANIZATION = "hannu"
IRC_NICK = "flowbotti#{rand(100).to_s}"
IRC_SERVER = "irc.stealth.net"
IRC_CHANNEL = "#fdtest" #channel [password]
IRC_REALNAME = "Flowdock IRC Bot"

class FlowDockBot < Isaac::Bot
  attr_accessor :gateway
end

class FlowdockIRC
  # Personal API token to get flow info and for API access
  # Get it from https://www.flowdock.com/account/tokens
  attr_accessor :bot, :flow, :latest_messages

  def initialize
    puts "Starting Flowdock IRC Bot"
    @latest_messages = []
    init_bot
    load_flow_info
  end

  def init_bot
    @bot = FlowDockBot.new do
      configure do |c|
        c.nick    = IRC_NICK
        c.server  = IRC_SERVER
        c.port    = 6667
        c.realname = IRC_REALNAME
      end
      on :connect do
        puts "Connected to IRC!"
        join IRC_CHANNEL
      end
      on :channel, // do
        # We want to store few latest message sent to flowdock
        # so those are not rendered in IRC again
        @gateway.latest_messages << "#{nick}: #{message}"
        while @gateway.latest_messages.size > 10 do
          @gateway.latest_messages.pop(0)
        end
        # Send message to flow
        @gateway.send_to_flowdock(nick, message)
      end
      on :error do
        # TODO: Error handling
        puts "An IRC bot error occurred"
      end
    end
    @bot.gateway = self
  end

  def id_to_nick(id)
    user = @flow['users'].select{|user| user['id'].to_s == id.to_s}.first
    user ? user['nick'] : id
  end

  def send_to_irc(nick, message)
    # Split possible password out from channel name
    @bot.msg(IRC_CHANNEL.split(' ').first, "<#{nick}> #{message}")
  end

  def send_to_flowdock(nick, message)
    uri = URI("https://api.flowdock.com/flows/#{ORGANIZATION}/#{FLOW}/messages")
    http = Net::HTTP.new(uri.host, 443)
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    http.use_ssl = true
    req = Net::HTTP::Post.new(uri.request_uri, initheader = {'Content-Type' =>'application/json'})
    req.basic_auth PERSONAL_TOKEN, ''
    req.body = {
      "event" => "message",
      "content" => message,
      "external_user_name" => nick
    }.to_json
    http.start() do |http|
      res = http.request(req)
      puts res.body
    end
  end

  def load_flow_info
    puts "Loading flow info..."
    uri = URI("https://api.flowdock.com/flows/#{ORGANIZATION}/#{FLOW}")
    http = Net::HTTP.new(uri.host, 443)
    http.use_ssl = true
    http.start() do |http|
      req = Net::HTTP::Get.new(uri.request_uri)
      req.basic_auth PERSONAL_TOKEN, ''
      res = http.request(req)
      raise "Could not load flow info. Invalid PERSONAL_TOKEN?" if res.code != '200'
      @flow = JSON.parse(res.body)
    end
  end

  def flowdock_stream
    http = EM::HttpRequest.new("https://stream.flowdock.com/flows/#{ORGANIZATION}/#{FLOW}").get(
      :head => {'Authorization' => [PERSONAL_TOKEN, ''], 'Accept' => 'text/json'}, 
      :keepalive => true, 
      :connect_timeout => 0, 
      :inactivity_timeout => 0
    )
    http.errback {|err| EM.stop}
    buffer = "" 
    http.stream do |chunk|
      buffer << chunk
      while line = buffer.slice!(/.+\r\n/)
        data = JSON.parse(line)
        # We want only messages and not the ones sent from IRC itself
        if data['event'] == "message" 
          latest = @latest_messages.index{|n| "#{data['external_user_name']}: #{data['content']}"}
          if latest
            @latest_messages.delete_at(latest)
          else
            send_to_irc(id_to_nick(data['user']), data['content'])
          end
        end
      end
    end
  end

  def run
    Thread.new {bot.start}
    while(true) do 
      EventMachine.run {flowdock_stream}
    end
  end
end

FlowdockIRC.new.run