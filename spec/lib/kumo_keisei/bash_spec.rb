require 'spec_helper'
require 'kumo_keisei/bash'

describe KumoKeisei::Bash do

  it "runs bash and returns output" do
    expect(KumoKeisei::Bash.new.execute("echo 1")).to eq("1")
  end

  it 'raises an exception if returned a non-zero exit code' do
    expect { KumoKeisei::Bash.new.execute('false') }.to raise_error(RuntimeError)
  end

end