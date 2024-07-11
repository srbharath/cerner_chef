require 'json'

# Path to the local JSON file
data_bag_path = '/tmp/kitchen/cache/cookbooks/my_cookbook/files/default/databag-test.json'

# Read and parse the JSON file
data_bag_item = JSON.parse(File.read(data_bag_path))

# Get the folder name from the data bag item
folder_name = data_bag_item['folder_name']

# Create the folder
directory folder_name do
  action :create
end

log "Folder '#{folder_name}' created successfully." do
  level :info
end

