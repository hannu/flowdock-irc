require 'rubygems' if RUBY_VERSION < '1.9'
require 'eventmachine'
require 'em-http'
require 'net/http'
require 'net/https'
require 'json'
require 'isaac/bot'

# Personal API token to get flow info and for API access
# Get it from https://www.flowdock.com/account/tokens
PERSONAL_TOKEN = ""

# Route configuration
# One to many mappings are also possible with 
# 'org/flow' => ['#chan1', '#chan2']
FLOW_TO_IRC = {
  "org/flow" => "#flowdock-bot"
}
IRC_TO_FLOW = {
  "#flowdock-bot" => "org/flow"
}

# IRC bot configuration
IRC_NICK = "flowbotti#{rand(100).to_s}"
IRC_SERVER = "irc.stealth.net"
IRC_REALNAME = "Flowdock IRC Bot"

class FlowDockBot < Isaac::Bot
  attr_accessor :gateway
end

class FlowdockIRC
  attr_accessor :bot, :flows, :latest_messages

  def initialize
    puts "Starting Flowdock IRC Bot"
    @latest_messages = []
    # Init IRC bot
    init_bot
    # Load flow info to get id -> nick mappings
    @flows = {}
    puts "Loading flow info..."
    FLOW_TO_IRC.keys.each do |flow|
      puts "- #{flow}"
      @flows[flow] = load_flow_info(flow)
    end
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
        puts "Connected to #{IRC_SERVER}"
        puts "I'm #{IRC_NICK}"
        puts "Joining to channels..."
        @gateway.all_channels.each do |channel|
          puts "- #{channel}"
          join channel
        end
      end
      on :channel, // do
        # We want to store few latest message sent to flowdock
        # so those are not rendered in IRC again
        @gateway.latest_messages << "#{nick}@#{channel}: #{message}"
        while @gateway.latest_messages.size > 10 do
          @gateway.latest_messages.pop(0)
        end
        # Send message to flows
        @gateway.flow_targets_for(channel).each do |flow|
          @gateway.send_to_flowdock(flow, nick, message)
        end
      end
      on :error do
        # TODO: Error handling
        puts "An IRC bot error occurred"
      end
    end
    @bot.gateway = self
  end

  def all_channels
    channels = (FLOW_TO_IRC.values + IRC_TO_FLOW.keys).flatten.uniq
    # Filter out nicks
    channels = channels.select{|c| ['#','!','&'].include?(c[0,1])}
    # Remove channels from list that are already there with password
    channels.select{|c| c.split(' ').size > 1}.each do |c|
      channels.delete(c.split(' ').first)
    end
    channels
  end

  def id_to_nick(flow, id)
    flow = flow.gsub(':', '/')
    return id unless @flows[flow]
    user = @flows[flow]['users'].select{|user| user['id'].to_s == id.to_s}.first
    user ? user['nick'] : id
  end

  def load_flow_info(flow)
    uri = URI("https://api.flowdock.com/flows/#{flow}")
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

  def flow_targets_for(channel)
    return IRC_TO_FLOW[channel].to_a if IRC_TO_FLOW[channel]
    []
  end

  def send_to_flowdock(flow, nick, message)
    uri = URI("https://api.flowdock.com/flows/#{flow}/messages")
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
      if res.code != '200'
        puts "ERROR: Could not send message to Flowdock"
        puts res.body
      end
    end
  end

  def irc_targets_for(flow)
    flow = flow.gsub(':', '/')
    return FLOW_TO_IRC[flow].to_a.map{|c| c.split(' ').first} if FLOW_TO_IRC[flow]
    []
  end

  def send_to_irc(channel, message)
    # Split possible password out from channel name
    @bot.msg(channel.split(' ').first, message)
  end

  def sent_from_channel?(nick, channel, message)
    latest = @latest_messages.index{|n| "#{nick}@#{channel}: #{message}"}
    @latest_messages.delete_at(latest) and return true if latest
    false
  end

  def handle_message(nick, channel, data)
    # We want only messages and not the ones sent from current channel itself
    return if sent_from_channel?(data['external_user_name'], channel, data['content'])
    send_to_irc(channel, "#{nick}: #{data['content']}")
  end

  def handle_status(nick, channel, data)
    send_to_irc(channel, "#{nick} changed status to: #{data['content']}")
  end

  def handle_comment(nick, channel, data)
    send_to_irc(channel, "#{nick} commented '#{data['content']['title']}': #{data['content']['text']}")
  end

  def handle_user_edit(nick, channel, data)
    return if nick == data['content']['user']['nick']
    send_to_irc(channel, "#{nick} is now known as #{data['content']['user']['nick']}")
  end

  def flowdock_stream
    http = EM::HttpRequest.new("https://stream.flowdock.com/flows/?filter=#{FLOW_TO_IRC.keys.join(',')}").get(
      :head => {'Authorization' => [PERSONAL_TOKEN, ''], 'Accept' => 'text/json'}, 
      :keepalive => true, 
      :connect_timeout => 0, 
      :inactivity_timeout => 0
    )
    # FIXME: This occurs somehow always after 10s idle
    http.errback {|err| EM.stop}
    buffer = "" 
    http.stream do |chunk|
      buffer << chunk
      while line = buffer.slice!(/.+\r\n/)
        data = JSON.parse(line)
        puts data.inspect
        if ["message", "status", "comment", "user-edit"].include?(data['event'])
          nick = id_to_nick(data['flow'], data['user'])
          event_method = data['event'].gsub('-','_')
          irc_targets_for(data['flow']).each do |channel|
            self.send("handle_#{event_method}", nick, channel, data)
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