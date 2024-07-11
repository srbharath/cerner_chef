require 'chef'

# Path to the local JSON file
data_bag_path = '/root/data_bags/hello/hellofolder.json'

# Read and parse the JSON file
data_bag_item = JSON.parse(File.read(data_bag_path))

# Get the folder name from the data bag item
folder_name = data_bag_item['folder_name']

# Create the folder
Dir.mkdir(folder_name) unless Dir.exist?(folder_name)

puts "Folder '#{folder_name}' created successfully."

