require 'spec_helper'

describe KumoKeisei::EnvironmentConfig do
  let(:env_name) { 'the_jungle' }
  let(:config_dir_path) { '/var/config' }
  let(:options) do
    {
      env_name: env_name,
      config_dir_path: config_dir_path,
      params_template_file_path: params_template_file_path
    }
  end
  let(:file_loader) { instance_double(KumoKeisei::FileLoader) }
  let(:parameter_template) { "stack_name: <%= config['stack_name'] %>" }
  let(:params_template_file_path) { '/junk.txt' }
  let(:environment_config_file_name) { "#{env_name}.yml" }
  let(:kms) { instance_double(KumoKi::KMS) }
  let(:logger) { double(:test_logger, debug: nil) }

  before do
    allow(KumoKeisei::FileLoader).to receive(:new).and_return(file_loader)
    allow(KumoKi::KMS).to receive(:new).and_return(kms)
    allow(file_loader).to receive(:load_config!).with(params_template_file_path).and_return(parameter_template)
  end

  describe '#cf_params' do
    subject { described_class.new(options, logger).cf_params }

    context 'params template file path is not provided' do
      let(:options) do
        {
          env_name: env_name,
          config_dir_path: config_dir_path
        }
      end

      it 'creates an empty array' do
        expect(subject).to eq([])
      end
    end

    context 'params file is empty' do
      let(:parameter_template) { nil }

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

    context 'templated params' do
      let(:environment_parameters) { { "stack_name" => "okonomiyaki" } }

      context 'environment params' do
        it 'creates a array containing an aws formatted parameter hash' do
          allow(file_loader).to receive(:load_config).with('common.yml').and_return({})
          allow(file_loader).to receive(:load_config).with(environment_config_file_name).and_return(environment_parameters)

          expect(subject).to eq([{parameter_key: "stack_name", parameter_value: "okonomiyaki"}])
        end
      end
    end
  end

  describe "#config" do
    subject { described_class.new(options, logger).config }

    context 'injected config' do

      let(:options) do
        {
          env_name: env_name,
          config_dir_path: config_dir_path,
          params_template_file_path: params_template_file_path,
          injected_config: { "injected" => "yes" }
        }
      end

      let(:common_parameters) { { "stack_name" => "okonomiyaki" } }
      it 'adds injected config to the config hash' do
        allow(file_loader).to receive(:load_config).with('common.yml').and_return(common_parameters)
        allow(file_loader).to receive(:load_config).with(environment_config_file_name).and_return({})
        allow(file_loader).to receive(:load_config).with('development.yml').and_return({})

        expect(subject).to eq({ "stack_name" => "okonomiyaki", "injected" => "yes" })
      end
    end

    context 'common config' do
      let(:common_parameters) { { "stack_name" => "okonomiyaki" } }

      it 'creates a array containing an aws formatted parameter hash' do
        allow(file_loader).to receive(:load_config).with('common.yml').and_return(common_parameters)
        allow(file_loader).to receive(:load_config).with(environment_config_file_name).and_return({})
        allow(file_loader).to receive(:load_config).with('development.yml').and_return({})

        expect(subject).to eq('stack_name' => 'okonomiyaki')
      end
    end

    context 'merging common and environment specific configurations' do
      let(:environment_config) { {'image' => 'ami-5678'} }

      context 'with environmental overrides' do
        let(:parameter_template) { "image: <%= config['image'] %>" }
        let(:common_config) { {'image' => 'ami-1234'} }
        let(:env_name) { 'development' }

        it 'replaces the common value with the env value' do
          allow(file_loader).to receive(:load_config).with('common.yml').and_return(common_config)
          allow(file_loader).to receive(:load_config).with('development.yml').and_return(environment_config)

          expect(subject).to eq('image' => 'ami-5678')
        end
      end

      it 'falls back to a default environment if the requested one does not exist' do
        allow(file_loader).to receive(:load_config).with('common.yml').and_return({})
        allow(file_loader).to receive(:load_config).with("#{env_name}.yml").and_return({})
        expect(file_loader).to receive(:load_config).with("development.yml").and_return(environment_config)

        expect(subject).to eq('image' => 'ami-5678')
      end
    end
  end

  describe "#plain_text_secrets" do
    subject { described_class.new(options, logger).plain_text_secrets }

    let(:crypted_password) { 'lookatmyencryptedpasswords' }
    let(:plain_text_password) { 'plain_text_password' }
    let(:secrets) { { 'secret_password' => "[ENC,#{crypted_password}" } }

    let(:crypted_env_password) { 'cryptedenvpassword' }
    let(:plain_text_env_password) { 'plain_text_env_password' }
    let(:env_secrets) { { 'secret_password' => "[ENC,#{crypted_env_password}"}}

    before do
      allow(kms).to receive(:decrypt).with(crypted_password).and_return(plain_text_password)
    end

    it 'decrypts common secrets' do
      allow(file_loader).to receive(:load_config).with('common_secrets.yml').and_return(secrets)
      allow(file_loader).to receive(:load_config).with("#{env_name}_secrets.yml").and_return({})
      allow(file_loader).to receive(:load_config).with("development_secrets.yml").and_return({})

      expect(subject).to eq('secret_password' => plain_text_password)
    end

    it 'decrypts environment secrets' do
      allow(file_loader).to receive(:load_config).with('common_secrets.yml').and_return({})
      allow(file_loader).to receive(:load_config).with("#{env_name}_secrets.yml").and_return(secrets)

      expect(subject).to eq('secret_password' => plain_text_password)
    end

    it 'gives preference to environment secrets' do
      allow(file_loader).to receive(:load_config).with('common_secrets.yml').and_return(secrets)
      allow(file_loader).to receive(:load_config).with("#{env_name}_secrets.yml").and_return(env_secrets)
      allow(kms).to receive(:decrypt).with(crypted_env_password).and_return(plain_text_env_password)

      expect(subject).to eq('secret_password' => plain_text_env_password)
    end

    it 'falls back to a default environment if the requested one does not exist' do
      allow(file_loader).to receive(:load_config).with('common_secrets.yml').and_return({})
      allow(file_loader).to receive(:load_config).with("#{env_name}_secrets.yml").and_return({})
      expect(file_loader).to receive(:load_config).with("development_secrets.yml").and_return(secrets)

      expect(subject).to eq('secret_password' => plain_text_password)
    end
  end
end
