# Fetch container ID and connect to custom_network
execute 'create_user' do
    command <<-EOH
      /opt/splunk/bin/splunk add user admin2 -role admin -password test@admin
      /opt/splunk/bin/splunk edit cluster-config -mode master -replication_factor 3 -search_factor 2 -secret test@123 -cluster_label test-index -auth admin2:test@admin
      /opt/splunk/bin/splunk restart
    EOH
    action :run
  end
