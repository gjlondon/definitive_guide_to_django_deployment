#
# Author:: Noah Kantrowitz <noah@opscode.com>
# Cookbook Name:: application_python
# Provider:: django
#
# Copyright:: 2011, Opscode, Inc <legal@opscode.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'tmpdir'

include Chef::DSL::IncludeRecipe

action :before_compile do

  include_recipe 'python'

  new_resource.migration_command "#{::File.join(new_resource.virtualenv, "bin", "python")} manage.py syncdb --noinput" if !new_resource.migration_command

  new_resource.symlink_before_migrate.update({
    new_resource.local_settings_base => new_resource.local_settings_file,
  })
end

action :before_deploy do

  install_packages

  created_settings_file

end

action :before_migrate do
  raise "fa"
  if new_resource.requirements.nil?
    # look for requirements.txt files in common locations
    [
      ::File.join(new_resource.release_path, "requirements", "#{node.chef_environment}.txt"),
      ::File.join(new_resource.release_path, "requirements.txt")
    ].each do |path|
      if ::File.exists?(path)
        new_resource.requirements path
        break
      end
    end
  end
  if new_resource.requirements
    Chef::Log.info("Installing using requirements file: #{new_resource.requirements}")
    pip_cmd = ::File.join(new_resource.virtualenv, 'bin', 'pip')
    execute "#{pip_cmd} install --source=#{Dir.tmpdir} -r #{new_resource.requirements}" do
      cwd new_resource.release_path
      # seems that if we don't set the HOME env var pip tries to log to /root/.pip, which fails due to permissions
      # setting HOME also enables us to control pip behavior on per-project basis by dropping off a pip.conf file there
      # GIT_SSH allow us to reuse the deployment key used to clone the main
      # repository to clone any private requirements
      if new_resource.deploy_key
        environment 'HOME' => ::File.join(new_resource.path,'shared'), 'GIT_SSH' => "#{new_resource.path}/deploy-ssh-wrapper"
      else
        environment 'HOME' => ::File.join(new_resource.path,'shared')
      end
      user new_resource.owner
      group new_resource.group
    end
  else
    Chef::Log.debug("No requirements file found")
  end

end

action :before_symlink do
  raise "la"
  if new_resource.collectstatic
    cmd = new_resource.collectstatic.is_a?(String) ? new_resource.collectstatic : "collectstatic --noinput"
    execute "#{::File.join(new_resource.virtualenv, "bin", "python")} manage.py #{cmd}" do
      user new_resource.owner
      group new_resource.group
      cwd new_resource.release_path
    end
  end

  ruby_block "remove_run_migrations" do
    block do
      if node.role?("#{new_resource.application.name}_run_migrations")
        Chef::Log.info("Migrations were run, removing role[#{new_resource.name}_run_migrations]")
        node.run_list.remove("role[#{new_resource.name}_run_migrations]")
      end
    end
  end

end

action :before_restart do
  raise "ffa"
end

action :after_restart do
end

protected

def install_packages
  python_virtualenv new_resource.virtualenv do
    path new_resource.virtualenv
    owner new_resource.owner
    group new_resource.group
    action :create
  end

  new_resource.packages.each do |name, ver|
    python_pip name do
      version ver if ver && ver.length > 0
      virtualenv new_resource.virtualenv
      user new_resource.owner
      group new_resource.group
      action :install
    end
  end
end

def created_settings_file
  new_resource.database_host ||= new_resource.find_database_server(new_resource.database_master_role)

  template "#{new_resource.path}/shared/#{new_resource.local_settings_base}" do
    source new_resource.settings_template || "settings.py.erb"
    cookbook new_resource.cookbook_name ? new_resource.cookbook_name.to_s : "application_python"
    owner new_resource.owner
    group new_resource.group
    new_resource.database["engine"] = new_resource.database_engine
    new_resource.database["database"] = new_resource.database_name
    new_resource.database["username"] = new_resource.database_username
    new_resource.database["password"] = new_resource.database_password
    mode "644"
    variables new_resource.settings.clone
    variables.update :debug => new_resource.debug, :database => {
      :host => new_resource.database_host,
      :settings => new_resource.database,
      :legacy => new_resource.legacy_database_settings
    }
  end
end
