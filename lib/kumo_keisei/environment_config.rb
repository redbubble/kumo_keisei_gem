require 'kumo_ki'
require 'logger'
require 'yaml'

require_relative 'file_loader'
require_relative 'parameter_builder'

class KumoKeisei::EnvironmentConfig
  LOGGER = Logger.new(STDOUT)

  attr_reader :app_name, :env_name

  def initialize(options, logger = LOGGER)
    @app_name = options[:app_name]
    @env_name = options[:env_name]
    @config_dir_path = options[:config_dir_path]
    @params_template_file_path = options[:params_template_file_path]
    @injected_config = options[:injected_config] || {}
    @file_loader = KumoKeisei::FileLoader.new(options)

    @log = logger
  end

  def get_binding
    binding()
  end

  def production?
    env_name == "production"
  end

  def development?
    !(%w(production staging).include?(env_name))
  end

  def plain_text_secrets
    @plain_text_secrets ||= decrypt_secrets(encrypted_secrets)
  end

  def config
    # a hash of all settings that apply to this environment
    load_config
  end

  def cf_params
    # returns a list of Cfn friendly paramater_value, paramater_key pairs for
    # consumption by cloudformation.
    return [] unless params
    load_config

    stack_params = YAML.load(params.result(binding()))
    KumoKeisei::ParameterBuilder.new(stack_params).params
  end

  private

  def load_config
    @config ||= common_config.merge(env_config).merge(@injected_config)
  end

  def kms
    @kms ||= KumoKi::KMS.new
  end

  def params
    return nil unless @params_template_file_path
    @file_loader.load_erb(@params_template_file_path)
  end

  def decrypt_secrets(secrets)
    Hash[
      secrets.map do |name, cipher_text|
        @log.debug "Decrypting '#{name}'"
        if cipher_text.start_with? '[ENC,'
          begin
            [name, "#{kms.decrypt cipher_text[5,cipher_text.size]}"]
          rescue
            @log.error "Error decrypting secret '#{name}'"
            raise
          end
        else
          [name, cipher_text]
        end
      end
    ]
  end

  def env_config_file_name
    "#{env_name}.yml"
  end

  def env_secrets_file_name
    "#{env_name}_secrets.yml"
  end

  def encrypted_secrets
    encrypted_common_secrets.merge(encrypted_env_secrets)
  end

  def encrypted_common_secrets
    @file_loader.load_hash('common_secrets.yml', optional=true)
  end

  def encrypted_env_secrets
    secrets = @file_loader.load_hash(env_secrets_file_name, optional=true)

    if !secrets.empty?
      secrets
    else
      @file_loader.load_hash('development_secrets.yml', optional=true)
    end
  end

  def common_config
    @file_loader.load_hash('common.yml', optional=true)
  end

  def env_config
    config = @file_loader.load_hash(env_config_file_name, optional=true)
    if !config.empty?
      config
    else
      @file_loader.load_hash('development.yml', optional=true)
    end
  end
end
