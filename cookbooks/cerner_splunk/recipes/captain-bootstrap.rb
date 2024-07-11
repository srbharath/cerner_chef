# Cookbook:: cerner_splunk
# Recipe:: captain-bootstrap
# This recipe initializes the Splunk search head cluster captain and restarts it.

# Define variables
splunk_home = "/opt/splunk"
servers_list = "https://172.17.0.2:8089,https://172.17.0.3:8089,https://172.17.0.4:8089"
auth_credentials = "admin2:test@admin"

# Restart the Splunk instance and add the user
execute 'choose captain and restart_splunk' do
  command <<-EOH
    sleep 30
    export SPLUNK_HOME=#{splunk_home}
    $SPLUNK_HOME/bin/splunk bootstrap shcluster-captain -servers_list "#{servers_list}" -auth #{auth_credentials}
    $SPLUNK_HOME/bin/splunk restart
  EOH
  action :run
end

