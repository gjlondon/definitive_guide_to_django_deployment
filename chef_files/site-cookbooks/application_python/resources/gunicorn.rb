#
# Author:: Noah Kantrowitz <noah@opscode.com>
# Cookbook Name:: application_python
# Resource:: gunicorn
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

attribute :app_module, :kind_of => [String, Symbol, NilClass], :default => nil
# Actually defaults to "settings.py.erb", but nil means it wasn't set by the user
attribute :settings_template, :kind_of => [String, NilClass], :default => nil
attribute :host, :kind_of => String, :default => '0.0.0.0'
attribute :port, :kind_of => Integer, :default => 8080
attribute :bind, :kind_of => String, :default => nil
attribute :backlog, :kind_of => Integer, :default => 2048
attribute :workers, :kind_of => Integer, :default => (node['cpu'] && node['cpu']['total']) && [node['cpu']['total'].to_i * 4, 8].min || 8
attribute :worker_class, :kind_of => [String, Symbol], :default => :sync
attribute :worker_connections, :kind_of => Integer, :default => 1000
attribute :max_requests, :kind_of => Integer, :default => 0
attribute :timeout, :kind_of => Integer, :default => 30
attribute :keepalive, :kind_of => Integer, :default => 2
attribute :debug, :kind_of => [TrueClass, FalseClass], :default => false
attribute :trace, :kind_of => [TrueClass, FalseClass], :default => false
attribute :preload_app, :kind_of => [TrueClass, FalseClass], :default => false
attribute :daemon, :kind_of => [TrueClass, FalseClass], :default => false
attribute :pidfile, :kind_of => [String, NilClass], :default => nil
attribute :umask, :kind_of => [String, Integer], :default => 0
attribute :logfile, :kind_of => String, :default => '-'
attribute :loglevel, :kind_of => [String, Symbol], :default => :info
attribute :proc_name, :kind_of => [String, NilClass], :default => nil
attribute :virtualenv, :kind_of => String, :default => nil
attribute :packages, :kind_of => [Array, Hash], :default => []
attribute :requirements, :kind_of => [NilClass, String, FalseClass], :default => nil
attribute :environment, :kind_of => [Hash], :default => {}
attribute :directory, :kind_of => [NilClass, String], :default => nil
