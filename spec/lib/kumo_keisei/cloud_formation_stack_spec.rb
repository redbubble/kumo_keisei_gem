require 'spec_helper'

describe KumoKeisei::CloudFormationStack do

  describe "#logical_resource" do

    let(:bash) { double('bash') }

    subject { KumoKeisei::CloudFormationStack.new(stack: "my-stack") }

    it "returns details for a resource" do
      allow(KumoKeisei::Bash).to receive(:new).and_return(bash)

      expect(bash).to receive(:execute).with("aws cloudformation describe-stack-resource --stack-name=my-stack --logical-resource-id=my-resource").and_return('{"StackResourceDetail": { "key": "value"}}')

      expect(subject.logical_resource("my-resource")).to eq ({ "key" => "value"  })
    end
  end
end