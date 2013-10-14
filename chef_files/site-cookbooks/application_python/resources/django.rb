#
# Author:: Noah Kantrowitz <noah@opscode.com>
# Cookbook Name:: application_python
# Resource:: django
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

include ApplicationCookbook::ResourceBase

attribute :database_master_role, :kind_of => [String, NilClass], :default => nil
attribute :database_host, :kind_of => [String, NilClass], :default => nil
attribute :database_engine, :kind_of => [String, NilClass], :default => nil
attribute :database_name, :kind_of => [String, NilClass], :default => nil
attribute :database_username, :kind_of => [String, NilClass], :default => nil
attribute :database_password, :kind_of => [String, NilClass], :default => nil
attribute :packages, :kind_of => [Array, Hash], :default => []
attribute :requirements, :kind_of => [NilClass, String, FalseClass], :default => nil
attribute :legacy_database_settings, :kind_of => [TrueClass, FalseClass], :default => false
attribute :settings, :kind_of => Hash, :default => {}
# Actually defaults to "settings.py.erb", but nil means it wasn't set by the user
attribute :settings_template, :kind_of => [String, NilClass], :default => nil
attribute :local_settings_file, :kind_of => String, :default => 'local_settings.py'
attribute :debug, :kind_of => [TrueClass, FalseClass], :default => false
attribute :collectstatic, :kind_of => [TrueClass, FalseClass, String], :default => false

def local_settings_base
  local_settings_file.split(/[\\\/]/).last
end

def virtualenv
  "#{path}/shared/env"
end

def database(*args, &block)
  @database ||= Mash.new
  @database.update(options_block(*args, &block))
  @database
end
