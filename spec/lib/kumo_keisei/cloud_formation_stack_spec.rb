require 'spec_helper'

describe KumoKeisei::CloudFormationStack do

  let(:bash) { double('bash') }

  subject { KumoKeisei::CloudFormationStack.new(stack: "my-stack", base_template: "template.json") }

  before do
    allow(KumoKeisei::Bash).to receive(:new).and_return(bash)
  end

  describe "#apply!" do

    before do
      allow(bash).to receive(:exit_status_for).with("aws cloudformation describe-stack-resources --stack-name my-stack").and_return(stack_exists ? 0 : 1)
    end

    context "stack exists" do

      let(:stack_exists) { true }

      it "updates the stack" do

        allow(bash).to receive(:execute).with("aws cloudformation describe-stacks --stack-name my-stack").and_return('{"Stacks": [{ "StackStatus": "COMPLETE" }] }')
        expect(bash).to receive(:execute).with("aws cloudformation update-stack --stack-name my-stack --template-body file://template.json")
        subject.apply!
      end

    end

    context "stack doesn't exists" do

      let(:stack_exists) { false }

      it "updates the stack" do

        allow(bash).to receive(:execute).with("aws cloudformation describe-stacks --stack-name my-stack").and_return('{"Stacks": [{ "StackStatus": "COMPLETE" }] }')
        expect(bash).to receive(:execute).with("aws cloudformation create-stack --stack-name my-stack --template-body file://template.json")
        subject.apply!
      end

    end


  end

  describe "#logical_resource" do

    it "returns details for a resource" do

      expect(bash).to receive(:execute).with("aws cloudformation describe-stack-resource --stack-name=my-stack --logical-resource-id=my-resource").and_return('{"StackResourceDetail": { "key": "value"}}')

      expect(subject.logical_resource("my-resource")).to eq ({ "key" => "value"  })
    end
  end
end