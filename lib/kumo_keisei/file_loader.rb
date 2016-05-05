module KumoKeisei
  class FileLoader
    def initialize(options)
      @config_dir_path = options[:config_dir_path]
    end

    def load_config(file_name)
      file_path = File.join(@config_dir_path, file_name)
      return {} unless File.exist?(file_path)
      YAML.load(File.read(file_path))
    end
  end
end
