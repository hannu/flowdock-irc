Two-way Flowdock <-> IRC gateway
================================

Two-way gateway between Flowdock flows and IRC channels. One-to-many mappings are also possible. Messages are loaded using Flowdock Streaming API and send using REST API.

Requirements
------------

<pre>
gem install isaac
gem install eventmachine
gem install em-http
</pre>

Route configuration examples
----------------------

Map single flow to single channel use in both ways

```ruby
FLOW_TO_IRC = {
  "organization/flow" => "#channel"
}
IRC_TO_FLOW = {
  "#channel" => "organization/flow"
}
```

One flow could be mapped to multiple channel as well as one channel to multiple flows. IRC nicks could be also used as target route

```ruby
FLOW_TO_IRC = {
  "organization/flow2" => ["#chan2"],
  "organization/flow" => ["#chan1", "#chan2", "nick"]
}
IRC_TO_FLOW = {
  "#channel" => ["organization/flow", "organization/flow2"]
}
```

Password protected IRC channels

```ruby
FLOW_TO_IRC = {
  "organization/flow" => "#secret password"
}
```
