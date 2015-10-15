require 'spec_helper'
require 'kumo_keisei/bash'

describe KumoKeisei::Bash do

  before do
      allow($stdout).to receive(:puts)
  end

  describe "#execute" do

    let(:command_string) { "echo 1" }

    subject { KumoKeisei::Bash.new.execute(command_string) }

    it "runs bash and returns output" do
      expect(subject).to eq("1")
    end

    context "when  block is given" do

      let(:command_string) { "echo 'Hiya!' && false" }

      it { expect { |block| KumoKeisei::Bash.new.execute(command_string, &block) }.to yield_with_args('Hiya!', 1) }
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
