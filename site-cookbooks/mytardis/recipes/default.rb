#
# Cookbook Name:: mytardis
# Recipe:: default
#
# Copyright 2012, The University of Queensland
#
# All rights reserved - Do Not Redistribute
#
include_recipe "build-essential"
include_recipe "mytardis::nginx"

# The basics for Python & devel packages we need for buildout
mytardis_pkg_deps = [
  "gcc",
  "python-devel", 
  "openldap-devel", 
  "openssl-devel", 
  "libxml2-devel", 
  "libxslt-devel"
]
mytardis_pkg_deps.each do |pkg|
  package pkg do
    action :install
  end
end

ohai "reload_passwd" do
  action :nothing
  plugin "passwd"
end

user "mytardis" do
  action :create
  comment "MyTardis Large Data Repository"
  system true
  supports :manage_home => true
  notifies :reload, resources(:ohai => "reload_passwd"), :immediately
end

app_dirs = [
  "/opt/mytardis",  
  "/opt/mytardis/shared",
  "/var/lib/mytardis",
  "/var/log/mytardis"
]

app_links = {
  "/opt/mytardis/shared/data" => "/var/lib/mytardis",
  "/opt/mytardis/shared/log" => "/var/log/mytardis"
}

app_dirs.each do |dir|
  directory dir do
    owner "mytardis"
    group "mytardis"
  end
end

app_links.each do |k, v|
  link k do
    to v
    owner "mytardis"
    group "mytardis"
  end
end

cookbook_file "/opt/mytardis/shared/buildout.cfg" do
  action :create
  source "buildout.cfg"
  owner "mytardis"
  group "mytardis"
end

cookbook_file "/opt/mytardis/shared/settings.py" do
  action :create_if_missing
  source "settings.py"
  owner "mytardis"
  group "mytardis"
end

bash "install foreman" do
  code <<-EOH
  gem install foreman
  EOH
  only_if do 
    output = `foreman help`
    $?.exitstatus == 127
  end
end

deploy_revision "mytardis" do
  action :deploy
  deploy_to "/opt/mytardis"  
  repository "https://github.com/mytardis/mytardis.git"
  branch "master"
  user "mytardis"
  group "mytardis"
  symlink_before_migrate({"data" => "var", 
                          "log" => "log", 
                          "buildout.cfg" => "buildout-prod.cfg",
                          "settings.py" => "tardis/settings.py"})
  purge_before_symlink([])
  create_dirs_before_symlink([])
  symlinks({})
  before_symlink do
    current_release = release_path
    
    bash "mytardis_buildout_install" do
      user "mytardis"
      cwd current_release
      code <<-EOH
        export PYTHON_EGG_CACHE=/opt/mytardis/shared/egg-cache
        python setup.py clean
        find . -name '*.py[co]' -delete
        python bootstrap.py
        bin/buildout -c buildout-prod.cfg install
      EOH
    end
  end
  restart_command do
    current_release = release_path
    
    bash "mytardis_foreman_install_and_restart" do
      cwd current_release
      code <<-EOH
        foreman export upstart /etc/init -a mytardis -p 3031 -u mytardis -l /var/log/mytardis
        restart mytardis || start mytardis
      EOH
    end
  end
end
