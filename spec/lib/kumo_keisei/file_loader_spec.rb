require 'spec_helper'

describe KumoKeisei::FileLoader do
  describe "#load_hash when you set optional flag to true" do
    let(:config_dir_path) { '/the/garden/path' }
    let(:options) { { config_dir_path: config_dir_path } }
    let(:file_name) { 'environment.yml' }
    let(:full_file_path) { config_dir_path + '/' + file_name }

    subject { KumoKeisei::FileLoader.new(options).load_hash(file_name, optional = true) }

    context "when the file does not exist" do
      it "returns an empty hash" do
        expect(subject).to eq({})
      end
    end

    context "when the file does exist" do
      let(:file_contents) { 'key: value' }

      it "populates a hash" do
        expect(File).to receive(:read).with(full_file_path).and_return(file_contents)
        expect(subject).to eq({ 'key' => 'value' })
      end
    end
  end

  describe "#load_hash when you don't set optional flag to true" do
    let(:config_dir_path) { '/the/garden/path' }
    let(:options) { { config_dir_path: config_dir_path } }
    let(:file_name) { 'environment.yml' }
    let(:full_file_path) { config_dir_path + '/' + file_name }

    subject { KumoKeisei::FileLoader.new(options).load_hash(file_name) }

    context 'when the file does not exist' do
      it 'raises an error' do
        expect { subject }.to raise_error(Errno::ENOENT)
      end
    end

    context 'when the file exists' do
      let(:file_contents) { 'key: value' }

      it 'populates a hash' do
        expect(File).to receive(:read).with(full_file_path).and_return(file_contents)
        expect(subject).to eq({ 'key' => 'value' })
      end
    end
  end
end
