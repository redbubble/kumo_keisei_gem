module KumoKeisei
  class ConsoleJockey
    def self.flash_message(message)
      puts "\n\n"
      puts "###################=============================------------"
      puts message
      puts "------------=============================###################"
      puts "\n\n"
    end

    def self.write_line(message)
      puts message
    end
  end
end
