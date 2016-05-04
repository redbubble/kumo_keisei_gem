require 'kumo_ki'
require 'logger'
require 'yaml'

class KumoKeisei::EnvironmentConfig
  LOGGER = Logger.new(STDOUT)

  attr_reader :app_name, :env_name

  def initialize(options, logger = LOGGER)
    @app_name = options[:app_name]
    @env_name = options[:env_name]
    @config_dir_path = options[:config_dir_path]

    @log = logger
  end

  def get_binding
    binding
  end

  def stack_name
    "#{app_name}-#{env_name}"
  end

  def set_cf_stack(name, stack)
    @cf_stacks[name.to_sym] = stack
  end

  def deploy_tag
    production? ? "production" : "non-production"
  end

  def production?
    env_name == "production"
  end

  def development?
    !(%w(production staging).include?(env_name))
  end

  def plain_text_secrets
    @plain_text_secrets ||= decrypt_secrets(
      encrypted_secrets,
      encrypted_secrets_filename,
    )
  end

  def config
    @config ||= common_config.merge(raw_config)
    p @raw_config
    @config
  end

  def tags
    [deploy_tag]
  end

  def vpc_id
    @cf_stacks[:vpc].outputs('VpcId')
  end

  def vpc_subnets
    @cf_stacks[:vpc].outputs('SubnetIds')
  end

  def cf_params
    params_template = params_template('lol')
    return [] if params_template.empty?

    cf_params_json(get_stack_params(params_template))
  end

  private

  def get_stack_params(params_template)
    YAML.load(ERB.new(params_template).result(get_binding))
  end

  def cf_params_json(params_data)
    params_data.flat_map { |name, value| { parameter_key: name, parameter_value: value } }
  end

  def stack_file_params_file_path(stack_name)
    "/tmp/tutum_cf_file_params_stack_#{stack_name}"
  end

  def write_stack_params_file(params_file_json, stack_name)
    File.open(stack_file_params_file_path(stack_name), "w+") do |f|
      f.write(params_file_json)
    end
  end

  def params_template(stack_name)
    stack_template_filepath = File.expand_path(File.join("..", "..", "env", "cloudformation", "#{stack_name}.yml.erb"), __FILE__)
    File.read(stack_template_filepath)
  end

  def kms
    @kms ||= KumoKi::KMS.new
  end

  def decrypt_secrets(secrets, filename)
    Hash[
      secrets.map do |name, cipher_text|
        @log.debug "Decrypting '#{name}'"
        if cipher_text.start_with? '[ENC,'
          begin
            [name, "#{kms.decrypt cipher_text[5,cipher_text.size]}"]
          rescue
            @log.error "Error decrypting secret '#{name}' from '#{filename}'"
            raise
          end
        else
          [name, cipher_text]
        end
      end
    ]
  end

  def encrypted_secrets_path
    filepath = File.join(@config_dir_path, "#{env_name}_secrets.yml")
    filepath = File.join(@config_dir_path, "development_secrets.yml") unless File.exist?(filepath)
    filepath
  end

  def raw_config_path
    filepath = File.join(@config_dir_path, "#{env_name}.yml")
    filepath = File.join(@config_dir_path, "development.yml") unless File.exist?(filepath)
    filepath
  end

  def common_config_path
    File.join(@config_dir_path, "common.yml")
  end

  def encrypted_secrets_filename
    File.basename encrypted_secrets_path
  end

  def config_filename
    File.basename config_path
  end

  def encrypted_secrets
    return {} unless File.exist?(encrypted_secrets_path)
    @encrypted_secrets ||= YAML.load(ERB.new(File.read(encrypted_secrets_path)).result(get_binding))
  end

  def common_config
    return {} unless File.exist?(common_config_path)
    @common_config ||= YAML.load(ERB.new(File.read(common_config_path)).result(get_binding))
  end

  def raw_config
    return {} unless File.exist?(raw_config_path)
    @raw_config ||= YAML.load(ERB.new(File.read(raw_config_path)).result(get_binding))
  end
end
