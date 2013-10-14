name "application_server"
description "A node hosting a running Django/gunicorn process"

# `env_root` is the location to create a virtualenv
# the virtual env will have the name `app_name`-env
# `repo` is the github repo, assumed to be public, cloned into `env_root`/`app_name`-env/`app_name`
# `settings` is the settings file, assumed to be in settings/ at your repo's root

settings = Chef::EncryptedDataBagItem.load("config", "config_1")
postgres_pass = settings["POSTGRES_PASS"]
domain = settings["DOMAIN"]
app_name = settings["APP_NAME"]
repo = settings["REPO"]
github_user = settings["GITHUB_USER"]
database_ip = settings["DATABASE_IP"]
database_name = settings["DATABASE_NAME"]

default_attributes("site_domain" => domain,
                   "project_root" => "/home/ubuntu/sites",
                   "app_name" => app_name,
                   "repo" => "#{github_user}/#{repo}",
#                   "settings" => "__init__.py",
                    "ubuntu_packages" => [
                        "bash-completion",
                        "python-setuptools",
                        "python-pip",
                        "python-dev",
                        "libpq-dev"
                    ],
                    "pip_python_packages" => [
                        "virtualenv",
                    ],
                    "postgresql" => {
                    	"password" => {
                    		"postgres" => postgres_pass
                    	},
                        "database_ip" => database_ip,
                        "database_name" => database_name,
                    },
                    "memcached" => {
                        "listen" => "0.0.0.0"
                    }
                    )

run_list "recipe[django_application_server]"






