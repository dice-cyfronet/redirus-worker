# Redirus worker [![build status](https://secure.travis-ci.org/dice-cyfronet/redirus-worker.png)](https://travis-ci.org/dice-cyfronet/redirus-worker) [![Code Climate](https://codeclimate.com/github/dice-cyfronet/redirus-worker.png)](https://codeclimate.com/github/dice-cyfronet/redirus-worker) [![Dependency Status](https://gemnasium.com/dice-cyfronet/redirus-worker.png)](https://gemnasium.com/dice-cyfronet/redirus-worker) [![Coverage Status](https://coveralls.io/repos/dice-cyfronet/redirus-worker/badge.png?branch=master)](https://coveralls.io/r/dice-cyfronet/redirus-worker)

The redirus worker is responsible for consuming create/delete subdomain redirections,
generating the appropriate nginx configurations and reloading nginx.

## Requirements

**This project is designed for Linux operating systems.**

- Linux (tested on Ubuntu)
- Nginx
- Ruby 2.0+
- Redis (can be installed on separate server)

## Packages / Dependencies

Install the required packages (needed to compile Ruby and nginx):

```
sudo apt-get update

apt-get install autoconf bison build-essential libssl-dev libyaml-dev libreadline6 libreadline6-dev zlib1g zlib1g-dev g++ make libpcre3 libpcre3-dev libssl-dev
```

## Ruby

You can use ruby installed by ruby version managers such as [RVM](http://rvm.io/)
or [rbenv](https://github.com/sstephenson/rbenv), or install it globally from
sources. The following manual presents global installation.

Remove the old Ruby 1.8 if present

```
sudo apt-get remove ruby1.8
```

Download Ruby and compile it:

```
mkdir /tmp/ruby && cd /tmp/ruby
curl --progress ftp://ftp.ruby-lang.org/pub/ruby/2.1/ruby-2.1.2.tar.gz | tar xz
cd ruby-2.1.2
./configure --disable-install-rdoc
make
sudo make install
```

Install the Bundler Gem:

```
sudo gem install bundler --no-ri --no-rdoc
```

## Nginx installation

Download and compile nginx:

```
mkdir -p /tmp/nginx && cd /tmp/nginx
curl http://nginx.org/download/nginx-1.7.4.tar.gz | tar xz
cd nginx-1.7.4
./configure --with-http_ssl_module --prefix=/nginx/installation/path
make
make install
```

Update nginx configuration:

```
edit /nginx/installation/path/conf/nginx.conf
```

the simplest configuration may look as follows:

```
worker_processes  1;

pid /nginx/installation/path/nginx.pid;

events {
    worker_connections  1024;
}


http {
    include       mime.types;
    default_type  application/octet-stream;

    sendfile        on;

    keepalive_timeout  65;

    types_hash_max_size 2048;
    server_names_hash_bucket_size  128;

    include /path/to/generated/nginx/configurations/*;
}
```
Two elements from presented configuration need to be customized:
+ `/nginx/installation/path/nginx.pid` file where nginx pid will be written.
+ `/path/to/generated/nginx/configurations/*` path to the place where redirus
worker will be generating configurations specific to registered redirections. `*`
is necessary at the end in order to load all configurations from this directory.

If  nginx is to bind to a low-numbered port, e.g. port 80,
the following command needs to be executed as root:

```
# package required to invoke setcap
apt-get install libcap2-bin

# allow nginx to bind into low-numbered port
setcap 'cap_net_bind_service=+ep' /path/to/nginx/sbin/nginx
```

## Self signed certificate

In production environment valid certificate (with `*` in CN section) signed by trusted organization should be used. If you don't have such certificate than
you can generate self signed certificate:

```
mkdir /usr/share/ssl/certs/my-domain.pl
cd /usr/share/ssl/certs/my-domain.pl
(umask 077 && touch host.key host.cert host.info host.pem)
openssl genrsa 2048 > host.key
openssl req -new -x509 -nodes -sha1 -days 3650 -key host.key > host.cert
...[enter *.my-domain.pl for the Common Name]...
openssl x509 -noout -fingerprint -text < host.cert > host.info
cat host.cert host.key > host.pem
chmod 400 host.key host.pem
```

## Redirus worker installation

```bash
# Get code
git clone https://github.com/dice-cyfronet/redirus-worker.git

# Enter code dir
cd redirus-worker

# Install dependencies
gem install bundler
bundle install

# Copy configuration
cp config.yml.example config.yml

# Customise redis configuration and nginx config files locations
edit config.yml
```

## Example config.yml

```yaml
queues:
  - site_prefix
  - second_site_prefix

redis_url: redis://localhost:6379
namespace: redirus

nginx:
  configs_path: /path/to/generated/nginx/configurations/
  pid: /nginx/installation/path/nginx.pid
  http_template: |
    listen *:80;
  https_template: |
    listen *:443 ssl;
    ssl_certificate     /path/to/cert/dir/server.crt;
    ssl_certificate_key /path/to/cert/dir/server.key;
  config_template: |
    #{upstream}
    server {
      #{listen}
      server_name #{name}.my-domain.pl;
      server_tokens off;
      proxy_set_header X-Server-Address $scheme://#{name}.my-domain.pl;
      proxy_set_header Host $http_host;
      location / {
        proxy_pass http://#{upstream_name};
        #{properties}
      }
    }
  allowed_properties:
    - proxy_sent_timeout \d
    - proxy_read_timeout \d
```

Some elements from presented configuration need to be customized:
+ `/path/to/generated/nginx/configurations/` is the location where configuration
specific for concrete redirection will be created. Value of this path **need** to
be the same as in nginx configuration file.
+ `/nginx/installation/path/nginx.pid` is a file containing nginx pid. To this pid
`SIGHUP` signal will be sent, which will triggers nginx configuration reload.
+ `/path/to/cert/dir/server.crt` path to ssl certificate used in https redirections.
This certificate need to have `*` in CN field.
+ `/path/to/cert/dir/server.key` path to ssl certificate key file.

By using `http_template`, `https_template`, `config_template` and
`allowed_properties` you can customize how nginx configuration looks like for each
subdomain.

+ `http_template` is used when an http redirection is created
+ `https_template` is used when an https redirection is created
+ `config_template` is used for http and https redirections.
Inside this template, the `listen` variable section is specific to http or https
redirections.
+ `allowed_properties` is used to define allowed parameters which can be
passed in the generated configuration. Regular expressions can be used here.

For example - when a redirection with the following parameters is requested:

```ruby
Sidekiq::Client.push(
  'queue' => 'cyfronet',
  'class' => Redirus::Worker::AddProxy,
  'args' => ['subdomain', ['127.0.0.1:80'], :http, ["proxy_send_timeout 6000"]])
```

...then the following `/nginx/sites-enabled/subdomain_http` subdomain config file
will be created:

```
upstream subdomain_http {
  server 127.0.0.1:80;
}
server {
  listen *:8000;
  server_name subdomain.localhost;
  server_tokens off;
  location / {
    proxy_pass http://subdomain_http;
    proxy_send_timeout 6000;
  }
}
```

## Run

```bash
/path/to/nginx/sbin/nginx
bundle exec ./bin/run
```
## Starting using upstart

The first step is to modify upstart in order to allow normal users to invoke it:

Replace `/etc/dbus-1/system.d/Upstart.conf` with yr content presented below
to allow any user to invoke all upstart methods:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<!DOCTYPE busconfig PUBLIC
  "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
  "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">

<busconfig>
  <!-- Only the root user can own the Upstart name -->
  <policy user="root">
    <allow own="com.ubuntu.Upstart" />
  </policy>

  <!-- Allow any user to invoke all of the methods on Upstart, its jobs
       or their instances, and to get and set properties - since Upstart
       isolates commands by user. -->
  <policy context="default">
    <allow send_destination="com.ubuntu.Upstart"
       send_interface="org.freedesktop.DBus.Introspectable" />
    <allow send_destination="com.ubuntu.Upstart"
       send_interface="org.freedesktop.DBus.Properties" />
    <allow send_destination="com.ubuntu.Upstart"
       send_interface="com.ubuntu.Upstart0_6" />
    <allow send_destination="com.ubuntu.Upstart"
       send_interface="com.ubuntu.Upstart0_6.Job" />
    <allow send_destination="com.ubuntu.Upstart"
       send_interface="com.ubuntu.Upstart0_6.Instance" />
  </policy>
</busconfig>
```

Add the following to `${HOME}/.bash_profile` (where `${HOME}` is the home directory of the user who will run `upstart`):

```
if [ ! -f /var/run/user/$(id -u)/upstart/sessions/*.session ]
then
    /sbin/init --user --confdir ${HOME}/.init &
fi

if [ -f /var/run/user/$(id -u)/upstart/sessions/*.session ]
then
   export $(cat /var/run/user/$(id -u)/upstart/sessions/*.session)
fi
```

Copy upstart configuration files:

```
cd redirus-worker-directory
mkdir ${HOME}/.init

cp lib/support/upstart/redirus.conf ${HOME}/.init
cp lib/support/upstart/redirus-worker.conf ${HOME}/.init
cp lib/support/upstart/redirus-worker-1.conf ${HOME}/.init
cp lib/support/upstart/redirus-worker-nginx.conf ${HOME}/.init

# Specify user name, path under which the redirus worker is installed and
# the location of the nginx configuration directory to be created:
editor ${HOME}/.init/redirus.conf

# Similar as above, plus if you are using ruby version manager - uncomment and
# customize the appropriate section for rbenv or rvm
editor ${HOME}/.init/redirus-worker-1.conf

# Update path to nginx
editor ${HOME}/.init/redirus-worker-nginx.conf
```
After loggin off and back on you should be able to start/stop/restart redirus
using the following commands:

```
initctl start redirus
initctl stop redirus
initctl restart redirus
```

## Generating Add/Remove redirection requests

```ruby
require 'rubygems'
require 'redirus/worker'
require 'redirus/worker/add_proxy'
require 'redirus/worker/rm_proxy'

# configure sidekiq client
Sidekiq.configure_client do |c|
  c.redis = {
    namespace: Redirus::Worker.config.namespace,
    url: Redirus::Worker.config.redis_url,
    queue: Redirus::Worker.config.queues.first
  }
end

# add new redirection
Sidekiq::Client.push(
  'queue' => Redirus::Worker.config.queues.first,
  'class' => Redirus::Worker::AddProxy,
  'args' => ['subdomain', ['127.0.0.1'], :http, ["proxy_send_timeout 6000"]])

# remove redirection
Sidekiq::Client.push(
  'queue' => Redirus::Worker.config.queues.first,
  'class' => Redirus::Worker::RmProxy,
  'args' => ['subdomain', :http])
```

## Contributing

1. Fork the project
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new pull request
