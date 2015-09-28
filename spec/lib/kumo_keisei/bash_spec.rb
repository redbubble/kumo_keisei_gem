require 'spec_helper'
require 'kumo_keisei/bash'

describe KumoKeisei::Bash do

  it "runs bash and returns output" do
    expect(KumoKeisei::Bash.new.execute("echo 1")).to eq("1")
  end

end