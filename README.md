Two-way Flowdock <-> IRC gateway
================================

[![Build Status](https://secure.travis-ci.org/hannu/flowdock-irc.png?branch=master)](http://travis-ci.org/hannu/flowdock-irc)

Two-way gateway between Flowdock flows and IRC channels. One-to-many mappings are also possible. Messages are loaded using Flowdock Streaming API and send using REST API.

Currently chat messages, influx comments and status changes are supported.

Requirements
------------

json, [eventmachine](https://github.com/eventmachine/eventmachine), [em-http-request](https://github.com/igrigorik/em-http-request), [isaac](https://github.com/vangberg/isaac)

Install with

<pre>
bundle install
</pre>

Route configuration examples
----------------------

Map single flow to single channel in both directions

<pre>
FLOW_TO_IRC = {
  "organization/flow" => "#channel"
}
IRC_TO_FLOW = {
  "#channel" => "organization/flow"
}
</pre>

One flow could be mapped to multiple channels as well as one channel to multiple flows. IRC nicks could be also used as target route

<pre>
FLOW_TO_IRC = {
  "organization/flow2" => ["#chan2"],
  "organization/flow" => ["#chan1", "#chan2", "nick"]
}
IRC_TO_FLOW = {
  "#channel" => ["organization/flow", "organization/flow2"]
}
</pre>

Password protected IRC channels

<pre>
FLOW_TO_IRC = {
  "organization/flow" => "#secret password"
}
</pre>
