require 'flowdock-irc'

describe FlowdockIRC do
  describe "#all_channels" do
    it "should filter out nicks" do
      FlowdockIRC.new({
        :flow_to_irc => {"org/flow" => ['#chan1', 'nick1', '#chan2']},
        :irc_to_flow => {"!chan3" => "org/flow"}
      }).all_channels.should eq(['#chan1','#chan2','!chan3'])
    end

    it "should not include password protected channels twice" do
      FlowdockIRC.new({
        :flow_to_irc => {"org/flow" => "#chan1 password"},
        :irc_to_flow => {"#chan1" => "org/flow"}
      }).all_channels.should eq(['#chan1 password'])
    end
  end

  describe "routing" do
    before do
      @f = FlowdockIRC.new({
        :flow_to_irc => {
          "org/flow" => '#chan1',
          "org/multi-target" => ['#chan1','#chan2'],
          "org/secret" => '#secret password'
        },
        :irc_to_flow => {
        "#chan1" => "org/flow",
        "#chan2" => ["org/flow1","org/flow2"]
        }
      })
    end

    it "should handle basic two-way routing" do
      @f.irc_targets_for('org/flow').should eq(['#chan1'])
      @f.flow_targets_for('#chan1').should eq(['org/flow'])
    end

    it "should handle multiple flow targets" do
      @f.flow_targets_for('#chan2').should eq(['org/flow1','org/flow2'])
    end

    it "should handle multiple irc targets" do
      @f.irc_targets_for('org/multi-target').should eq(['#chan1','#chan2'])
    end

    it "should strip out password from irc channels" do
      @f.irc_targets_for('org/secret').should eq(['#secret'])
    end
  end
end