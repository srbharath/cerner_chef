# Restart the Splunk instance and add the user
execute 'restart_splunk' do
    command <<-EOH

      /opt/splunk/bin/splunk add user admin2 -role admin -password test@admin
      /opt/splunk/bin/splunk restart
    EOH
    action :run
  end
