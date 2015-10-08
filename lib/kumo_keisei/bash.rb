module KumoKeisei
  class Bash
    def execute(command)
      output = `#{command} 2>&1`.strip
      output
    end

    def exit_status_for(command)
      puts "Executing --> #{command}"
      `#{command}`
      $?.exitstatus
    end
  end
end
