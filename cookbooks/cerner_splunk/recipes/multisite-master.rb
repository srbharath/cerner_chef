execute 'create_user' do
    command <<-EOH
      /opt/splunk/bin/splunk add user admin2 -role admin -password test@admin
      /opt/splunk/bin/splunk restart
    EOH
    action :run
  end

