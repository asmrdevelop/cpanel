#!/bin/sh
eval 'if [ -x /usr/local/cpanel/3rdparty/bin/perl ]; then exec /usr/local/cpanel/3rdparty/bin/perl -x -- $0 ${1+"$@"}; else exec /usr/bin/perl -x -- $0 ${1+"$@"};fi'
    if 0;
#!/usr/bin/perl

# Plugin: CloudLinux Imunify360 VERSION:0.1
#
# Location: whostmgr/docroot/cgi/imunify360
# Copyright(c) 2010 CloudLinux, Inc.
# All rights Reserved.
# http://www.cloudlinux.com
#
#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#WHMADDON:imunify360:Imunify360

#Title: cPanel Imunify360 plugin.
#Version: 1.0
#Site: http://cloudLinux.com

BEGIN { unshift @INC, '/usr/local/cpanel', '/usr/local/cpanel/whostmgr/cgi/imunify/handlers'; }

use strict;
use warnings;
use locale ':not_characters';   # utf-8

use Whostmgr::ACLS          ();
use Cpanel::Form            ();
use Cpanel::SafeRun::Errors ();
use Cpanel::JSON;
use Data::Dumper qw(Dumper);
use CGI;
use Encode;

#use CGI::Carp qw(fatalsToBrowser); # uncomment to debug 500 error

use Imunify::File;
use Imunify::Exception;
use Imunify::Render;
use Imunify::Utils;
use Imunify::Wrapper;
use Imunify::Acls;

Whostmgr::ACLS::init_acls();

if (!Imunify::Acls::checkPermission()) {
    Imunify::Exception->new('Permission denied')->asJSON();
}

if ($ENV{ REQUEST_METHOD } ne 'POST') {
    Imunify::Exception->new('Method not allowed')->asJSON();
}

my $REQUEST;
my $command = 'default';
my %dispatchTable = (
    default => \&main,
    commandIE => \&commandIE,
    uploadFile => \&uploadFile,
);

$CGI::POST_MAX = 1024 * 1024 * 2;

eval {
    my $cgi = CGI->new();
    my $json = $cgi->param('POSTDATA');
    $command = $cgi->param('command');

    if ($json) {
        $REQUEST = Cpanel::JSON::Load($json);
        $command = $REQUEST->{'command'} || 'default';
        processRequest($command, $cgi);
    } elsif ($command) {
        processRequest($command, $cgi);
    } else {
        die Imunify::Exception->new('Empty dataset');
    }
};

if ($@) {
    if (ref($@) && $@->can('asJSON')) {
        $@->asJSON();
    } else {
        die Imunify::Exception->new($@)->asJSON();
    }
}

sub processRequest {
    my ($action, $cgi) = @_;
    $action = 'default' unless exists $dispatchTable{$action};
    $dispatchTable{$action}->($cgi);
}

sub main {
    Imunify::Wrapper::request($REQUEST, 1);
}

sub commandIE {
    Imunify::Wrapper::imunfyEmailRequest($REQUEST, 1);
}

sub uploadFile {
    my ($cgi) = @_;
    my $response = Imunify::Wrapper::upload($cgi, 1);
    Imunify::Render::JSONHeader(Imunify::Render->HTTP_STATUS_OK);
    print $response;
}
