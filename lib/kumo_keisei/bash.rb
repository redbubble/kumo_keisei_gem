module KumoKeisei
  class Bash
    def execute(command)
      output = `#{command} 2>&1`.strip
      raise "unexpected exit code: #{$?.exitstatus} when running #{command}: #{output}" unless $?.exitstatus == 0
      output
    end

    def exit_status_for(command)
      `#{command}`
      $?.exitstatus
    end
  end
end