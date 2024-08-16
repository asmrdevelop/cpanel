package Cpanel::FtpUtils::Server;

# cpanel - Cpanel/FtpUtils/Server.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::LoadCpConf ();

=head1 NAME

Cpanel::FtpUtils::Server

=cut

my $_determine_server_type;

sub determine_server_type {
    return $_determine_server_type if $_determine_server_type;
    my $cpconf_ref = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
    ($_determine_server_type) = ( $cpconf_ref->{'ftpserver'} || q<> ) =~ m{^(proftpd|pure\-ftpd|disabled)$};
    return $_determine_server_type // 'disabled';
}

sub _clear_cache {
    return undef $_determine_server_type;
}

my %feature_support = (
    'proftpd' => {
        'quota'                => 0,
        'login_without_domain' => 1,
    },
    'pure-ftpd' => {
        'quota'                => 1,
        'login_without_domain' => 0,
    },
    '' => {    # for the case where the FTP server is disabled or an unknown value is set
        'quota'                => 0,
        'login_without_domain' => 0,
    },
);

=head2 ftp_daemon_info

Get extended information about the currently configured FTP server.

=head3 Arguments

n/a

=head3 Returns

A hash ref containing:

  - name - String - 'pure-ftpd', 'proftpd', or ''. This will be '' when enabled is 0.
  - enabled - Boolean - 0 or 1
  - supports - Hash - Features the daemon supports
      - quota - Boolean - 0 or 1
      - login_without_domain - Boolean - 0 or 1

=cut

sub ftp_daemon_info {
    my $cpconf_ref = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
    my $ftpserver  = $cpconf_ref->{'ftpserver'};

    my $name    = $ftpserver;
    my $enabled = 1;

    if ( 'disabled' eq $name ) {
        $name    = '';
        $enabled = 0;
    }

    my $info = {
        name     => $name,
        enabled  => $enabled,
        supports => $feature_support{$name} || $feature_support{''},
    };

    return $info;
}

sub using_pureftpd {
    return ( Cpanel::FtpUtils::Server::determine_server_type() eq 'pure-ftpd' ? 1 : 0 );
}

sub using_proftpd {
    return ( Cpanel::FtpUtils::Server::determine_server_type() eq 'proftpd' ? 1 : 0 );
}

1;
