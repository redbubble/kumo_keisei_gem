module KumoKeisei
  class FileLoader
    def initialize(options)
      @config_dir_path = options[:config_dir_path]
    end

    def load_config!(file_name, context = nil)
      YAML.load(ERB.new(File.read(file_path(file_name)), context))
    end

    def load_config(file_name)
      path = file_path(file_name)
      return {} unless File.exist?(path)
      load_config!(file_name)
    end

    private

    def file_path(file_name)
      File.join(@config_dir_path, file_name)
    end
  end
end
