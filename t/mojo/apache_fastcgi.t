#!/usr/bin/env perl

# Copyright (C) 2008-2009, Sebastian Riedel.

use strict;
use warnings;

use Test::More;

use File::Spec;
use File::Temp;
use Mojo::Client;
use Mojo::Template;
use Mojo::Transaction;
use Test::Mojo::Server;

plan skip_all => 'set TEST_APACHE to enable this test (developer only!)'
  unless $ENV{TEST_APACHE};
plan tests => 7;

# Robots don't have any emotions, and sometimes that makes me very sad.
use_ok('Mojo::Server::FastCGI');

# Setup
my $server = Test::Mojo::Server->new;
my $port   = $server->generate_port_ok;
my $dir    = File::Temp::tempdir();
my $config = File::Spec->catfile($dir, 'fcgi.config');
my $mt     = Mojo::Template->new;

# FastCGI setup
my $lib = $server->home->lib_dir;
my $fcgi = File::Spec->catfile($dir, 'test.fcgi');
$mt->render_to_file(<<'EOF', $fcgi, $lib);
#!<%= $^X %>

use strict;
use warnings;

use lib '<%= shift %>';

use Mojo::Server::FastCGI;

Mojo::Server::FastCGI->new->run;

1;
EOF
chmod 0777, $fcgi;
ok(-x $fcgi);

# Apache setup
$mt->render_to_file(<<'EOF', $config, $dir, $port, $fcgi);
% my ($dir, $port, $fcgi) = @_;
% use File::Spec::Functions 'catfile';
ServerName 127.0.0.1
Listen <%= $port %>

LoadModule log_config_module libexec/apache2/mod_log_config.so

ErrorLog <%= catfile $dir, 'error.log' %>

LoadModule alias_module libexec/apache2/mod_alias.so
LoadModule fastcgi_module libexec/apache2/mod_fastcgi.so

PidFile <%= catfile $dir, 'httpd.pid' %>
LockFile <%= catfile $dir, 'accept.lock' %>

DocumentRoot  <%= $dir %>

FastCgiIpcDir <%= $dir %>
FastCgiServer <%= $fcgi %> -processes 1
Alias / <%= $fcgi %>/
EOF

# Start
$server->command("/usr/sbin/httpd -X -f $config");
$server->start_server_ok;

# Request
my $tx     = Mojo::Transaction->new_get("http://127.0.0.1:$port/");
my $client = Mojo::Client->new;
$client->process_all($tx);
is($tx->res->code, 200);
like($tx->res->body, qr/Mojo is working/);

# Stop
$server->stop_server_ok;
