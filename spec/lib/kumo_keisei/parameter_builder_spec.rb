describe KumoKeisei::ParameterBuilder do
  subject  {described_class.new(dynamic_params, file_path) }
  let(:dynamic_params) { {} }
  let(:file_path) { nil }
  let(:file_content) do
    [
      {
        "ParameterKey" => "testFileKey",
        "ParameterValue" => "testFileValue",
      },
    ]
  end

  describe '#params' do
    before do
      allow(File).to receive(:exist?).with(file_path).and_return(true)
      allow(File).to receive(:read).with(file_path).and_return(file_content.to_json)
    end

    context "when there are dynamic params" do
      let(:dynamic_params) { { key: 'value', other_key: 'other_value' } }
      it 'includes command line params' do
        expect(subject.params).to eq([{ parameter_key: 'key', parameter_value: 'value' }, { parameter_key: 'other_key', parameter_value: 'other_value'}])
      end
    end

    context "when there are file params" do
      let(:file_path) { '/some/path/to/params.json' }

      it 'includes an input file' do
        expect(subject.params).to eq([{ parameter_key: 'testFileKey', parameter_value: 'testFileValue' }])
      end
    end

    context "there are both" do
      let(:dynamic_params) { { key: 'value', other_key: 'other_value' } }
      let(:file_path) { '/some/path/to/params.json' }

      it 'includes command line params' do
        expect(subject.params).to eq([
          { parameter_key: 'key', parameter_value: 'value' },
          { parameter_key: 'other_key', parameter_value: 'other_value'},
          { parameter_key: 'testFileKey', parameter_value: 'testFileValue' }
        ])
      end
    end
  end
end
