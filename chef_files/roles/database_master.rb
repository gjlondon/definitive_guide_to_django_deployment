name "database_master"
description "Database master cluster"

settings = Chef::EncryptedDataBagItem.load("config", "config_1")
postgres_pass = settings["POSTGRES_PASS"]
db_name = settings["DATABASE_NAME"]

default_attributes(
	:postgresql => {
		:config => {:listen => '*'},
		:config_pgtune => {:db_type => "web"},
		:password => {"postgres" => postgres_pass},
		:db_name => db_name,
		:pg_hba => [{
			:comment => '# EC2 internal access',
			:type => 'host',
			:db => 'all',
			:user => 'postgres',
			:addr => "0.0.0.0/0",
			:method => 'md5'
		}]
	}

)

run_list(
  "recipe[django_application_server::database]"
)

