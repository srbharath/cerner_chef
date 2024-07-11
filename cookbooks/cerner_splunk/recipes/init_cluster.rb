# Cookbook:: my_cookbook
# Recipe:: init_shcluster
# This recipe initializes the Splunk search head cluster members and restarts them.

# Restart the Splunk instance and add the user
execute 'restart_splunk' do
    command <<-EOH

      /opt/splunk/bin/splunk add user admin2 -role admin -password test@admin
      /opt/splunk/bin/splunk restart
    EOH
    action :run
  end

# First, determine the container IP address
container_ip = `hostname -i`.strip

# Determine mgmt_uri and port based on container_ip
case container_ip
when '172.17.0.2'
  mgmt_uri = "https://172.17.0.2:8089"
  replication_port = 34568
when '172.17.0.3'
  mgmt_uri = "https://172.17.0.3:8089"
  replication_port = 34569
when '172.17.0.4'
  mgmt_uri = "https://172.17.0.4:8089"
  replication_port = 34570
else
  # Default mgmt_uri and replication_port if no specific case matches
  mgmt_uri = "https://64.23.228.40:8089"
  replication_port = 34567
end

# Define other parameters
replication_factor = 3
shcluster_label = 'shcluster1'
username = "admin2"
password = "test@admin"

# Define the content to be added to server.conf
shclustering_content = <<-EOF
[shclustering]
pass4SymmKey = test@123
shcluster_label = cluster_1
replication_port = #{replication_port}
EOF

# Ensure the content is added to server.conf
file '/opt/splunk/etc/system/local/server.conf' do
  content lazy { ::File.read('/opt/splunk/etc/system/local/server.conf') + shclustering_content }
  not_if { ::File.read('/opt/splunk/etc/system/local/server.conf').include?('[shclustering]') }
  action :create
end

# Execute the splunk init command
execute 'init_shcluster' do
  command "/opt/splunk/bin/splunk init shcluster-config -auth #{username}:#{password} -mgmt_uri #{mgmt_uri} -replication_port #{replication_port} -replication_factor #{replication_factor} -shcluster_label #{shcluster_label}"
  action :run
  not_if { ::File.exist?('/opt/splunk/etc/system/local/shcluster') }
end

# Restart the Splunk instance
execute 'restart_splunk' do
  command '/opt/splunk/bin/splunk restart'
  action :run
end

