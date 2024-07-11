require 'erb'
require 'yaml'

erb_file = 'kitchen.yml.erb'
yaml_file = 'kitchen.yml'

template = ERB.new(File.read(erb_file))
File.write(yaml_file, template.result(binding)) 

