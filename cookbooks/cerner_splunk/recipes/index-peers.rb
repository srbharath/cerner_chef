execute 'create_user and add peers to cluster' do
  command <<-EOH
    /opt/splunk/bin/splunk add user admin2 -role admin -password test@admin
    /opt/splunk/bin/splunk edit cluster-config -mode peer -manager_uri https://172.18.0.5:8089 -replication_port 9001 -secret test@123 -auth admin2:test@admin 
    /opt/splunk/bin/splunk restart
  EOH
  action :run
end
