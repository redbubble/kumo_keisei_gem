require 'spec_helper'

describe KumoKeisei::EnvironmentConfig do
  describe '#cf_params' do

    let(:env_name) { 'the_jungle' }
    let(:config_dir_path) { '/var/config' }
    let(:options) do
      {
        env_name: env_name,
        config_dir_path: config_dir_path
      }
    end
    let(:file_loader) { instance_double(KumoKeisei::FileLoader) }

    before do
      allow(File).to receive(:read).and_return(parameter_template)
      allow(KumoKeisei::FileLoader).to receive(:new).and_return(file_loader)
    end

    subject { described_class.new(options).cf_params }

    context 'no params' do
      let(:parameter_template) { '' }

      it 'creates an empty array' do
        expect(subject).to eq([])
      end
    end

    context 'a hard-coded param' do
      let(:parameter_template) { "parameter_key: <%= 'parameter_value' %>" }

      it 'creates a array containing an aws formatted parameter hash' do
        expect(subject).to eq([{parameter_key: "parameter_key", parameter_value: "parameter_value"}])
      end
    end

    context 'a templated param' do
      let(:parameter_template) { "stack_name: <%= config['stack_name'] %>" }
      let(:environment_config_file_name) { "#{env_name}.yml" }
      let(:environment_parameters) { { "stack_name" => "okonomiyaki" } }

      it 'creates a array containing an aws formatted parameter hash' do
        allow(file_loader).to receive(:load_config).with('common.yml').and_return({})
        allow(file_loader).to receive(:load_config).with(environment_config_file_name).and_return(environment_parameters)

        expect(subject).to eq([{parameter_key: "stack_name", parameter_value: "okonomiyaki"}])
      end
    end

    #TODO: Deal with common config merging
    #TODO: Deal with secrets
  end
end
