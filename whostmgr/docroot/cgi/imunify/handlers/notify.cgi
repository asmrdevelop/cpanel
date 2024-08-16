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

# logs can be found in /usr/local/cpanel/logs/error_log

BEGIN { unshift @INC, '/usr/local/cpanel', '/usr/local/cpanel/whostmgr/cgi/imunify/handlers'; }

use strict;

use Cpanel::JSON;
use Imunify::Icontact::MalwareFound;
use Imunify::Icontact::ScanNotScheduled;
use Imunify::Icontact::Generic;
use Data::Dumper;
use Capture::Tiny 'capture_stderr';

my $input = '';
foreach my $line (<>) {
    $input .= $line;
}
my $json_input = Cpanel::JSON::Load($input);
my $type = $json_input->{'message_type'};
my $user = $json_input->{'user'};
my $params = $json_input->{'params'};
if ( !defined($type) ) {
    die("In stdin json should be entry message_type\n");
}

if ($type ne 'MalwareFound' && $type ne 'ScanNotScheduled' && $type ne 'Generic') {
    die("message_type should be MalwareFound or ScanNotScheduled or Generic\n");
}

if ($type eq 'MalwareFound' && (!defined($params) || !defined($params->{infected_user}))) {
    die("MalwareFound should have param infected_user\n");
}

my $icontact_warnings = capture_stderr {
    my $icontact_instance;
    if ($type eq 'MalwareFound') {
        $icontact_instance = Cpanel::iContact::Class::Imunify::MalwareFound->new(
            infected_user => $params->{infected_user},
        );
    }
    if ($type eq 'ScanNotScheduled') {
        $icontact_instance = Cpanel::iContact::Class::Imunify::ScanNotScheduled->new();
    }
    if ($type eq 'Generic') {
        $icontact_instance = Cpanel::iContact::Class::Imunify::Generic->new(
            to => $user,
            username => $user,
            params => $params
        );
    }
    my %template_args = (
        $icontact_instance->_template_args(),
        'message_type' => $type,
        'params' => $params,
    );

    print Cpanel::JSON::SafeDump(\%template_args), "\n";
};

print "$icontact_warnings" if $icontact_warnings;

1;
