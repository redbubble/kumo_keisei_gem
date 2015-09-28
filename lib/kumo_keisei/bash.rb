module KumoKeisei
  class Bash
    def execute(command)
      `#{command}`.strip
    end
  end
end