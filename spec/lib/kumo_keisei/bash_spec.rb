require 'spec_helper'
require 'kumo_keisei/bash'

describe KumoKeisei::Bash do

  describe "#execute" do

    it "runs bash and returns output" do
      expect(KumoKeisei::Bash.new.execute("echo 1")).to eq("1")
    end

    it 'raises an exception if returned a non-zero exit code' do
      expect { KumoKeisei::Bash.new.execute('false') }.to raise_error(RuntimeError)
    end
  end

  describe "#exit_status_for" do

    it 'returns error codes' do
      expect(KumoKeisei::Bash.new.exit_status_for('false')).to eq(1)
    end

    it 'returns zero for sucessful commands' do
      expect(KumoKeisei::Bash.new.exit_status_for('true')).to eq(0)
    end
  end
end