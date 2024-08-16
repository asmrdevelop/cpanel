package Cpanel::Services::Installed;

# cpanel - Cpanel/Services/Installed.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Server::Type              ();
use Cpanel::Server::Type::License     ();
use Cpanel::Debug                     ();
use Cpanel::FindBin                   ();
use Cpanel::Binaries                  ();
use Cpanel::Chkservd::Config          ();
use Cpanel::Config::Httpd::EA4        ();
use Cpanel::Services::AlwaysInstalled ();

$Cpanel::Services::Installed::VERSION = '0.4';

my $find_path = [qw{ /sbin /usr/sbin /usr/local/sbin /bin /usr/bin /usr/local/bin /usr/local/cpanel/3rdparty/bin }];

sub _service_is_installed_clamd {
    require Cpanel::Binaries;
    if ( -x Cpanel::Binaries::path('clamd') ) {
        return 1;
    }
    return;
}

sub _service_is_installed_cpdavd {
    if ( Cpanel::Server::Type::is_dnsonly() ) { return 0; }
    return 1;
}

sub _service_is_installed_exim {
    if ( -x Cpanel::Binaries::path('exim') ) {
        return 1;
    }
    return;
}

sub _service_is_installed_exim_altport {
    if ( -x Cpanel::Binaries::path('exim') ) {
        return 1;
    }
    return;
}

sub _service_is_installed_ftpd {
    if ( Cpanel::Server::Type::is_dnsonly() ) { return 0; }
    if ( Cpanel::FindBin::findbin( 'pure-ftpd', 'path' => $find_path ) || Cpanel::FindBin::findbin( 'proftpd', 'path' => $find_path ) ) {
        return 1;
    }
    return;
}

sub _service_is_installed_httpd {
    if ( !Cpanel::Config::Httpd::EA4::is_ea4() )             { return 0; }
    if ( !Cpanel::Server::Type::License::is_full_license() ) { return 0; }
    return 1;
}

sub _service_is_installed_imap {
    if ( Cpanel::Server::Type::is_dnsonly() ) { return 0; }
    return 1;
}

sub _service_is_installed_pop {
    if ( Cpanel::Server::Type::is_dnsonly() ) { return 0; }
    return 1;
}

sub _service_is_installed_mailman {
    if ( Cpanel::Server::Type::is_dnsonly() ) { return 0; }
    return 1;
}

sub _service_is_installed_mysql {
    require Cpanel::DbUtils;
    if ( Cpanel::DbUtils::find_mysqld() ) {
        return 1;
    }
    return;
}

sub _service_is_installed_postgresql {
    require Cpanel::DbUtils;
    if ( Cpanel::DbUtils::find_postmaster() ) {
        return 1;
    }
    return;
}

sub _service_is_installed_cpanellogd {
    return 1;
}

sub _service_is_installed_rsyslogd {
    if ( Cpanel::FindBin::findbin( 'rsyslogd', 'path' => $find_path ) ) {
        return 1;
    }
    return;
}

sub _service_is_installed_spamd {
    if ( -x Cpanel::Binaries::path('spamd') ) {
        return 1;
    }
    return;
}

sub _service_is_installed_sshd {
    if ( -x Cpanel::FindBin::findbin('sshd') ) {
        return 1;
    }
    return;
}

sub _service_is_installed_crond {
    require Cpanel::OS;
    if ( -x Cpanel::OS::cron_bin_path() ) {
        return 1;
    }
    return;
}

sub _service_is_installed_nscd {
    if ( Cpanel::FindBin::findbin( 'nscd', 'path' => $find_path ) ) {
        return 1;
    }
    return;
}

sub _service_is_installed_syslogd {
    if ( Cpanel::FindBin::findbin( 'syslogd', 'path' => $find_path ) ) {
        return 1;
    }
    return;
}

sub _service_is_installed_p0f {
    if ( -e '/usr/local/cpanel/3rdparty/sbin/p0f' ) {
        return 1;
    }
    return 0;
}

sub _service_is_installed_apache_php_fpm {
    require Cpanel::PHPFPM::Controller;
    my $versions_ar = Cpanel::PHPFPM::Controller::get_phpfpm_versions();
    if ( @{$versions_ar} ) {
        return 1;
    }
    return 0;
}

sub _service_is_installed_pdns {
    return -x Cpanel::Binaries::path('pdns_server') ? 1 : 0;
}

# Handle a plugin like cpanel-dovecot-solr
sub _service_has_chkservd_file {
    return -e "$Cpanel::Chkservd::Config::chkservd_dir/$_[0]" ? 1 : 0;
}

# Builds a subroutine name based on the service argument
# tests to see if a sub of that name exists, then
# executes it.
#
sub service_is_installed {
    my ($service) = @_;
    if ( $service =~ tr{0-9A-Za-z_-}{}c ) {
        Cpanel::Debug::log_warn("[$service] doesn't look like a service name");
        return;
    }

    # need to handle the exim-altport service name and any future names with - in it
    # to be called with a _ instead in the subs above

    my $service_code_name = $service;
    $service_code_name =~ tr{-}{_};

    return 1 if grep { $_ eq $service_code_name } Cpanel::Services::AlwaysInstalled::SERVICES();

    my $is_installed = "_service_is_installed_$service_code_name";
    my $result       = undef;

    if ( my $code = __PACKAGE__->can($is_installed) ) {
        $result = $code->();
        return 1 if $result;
    }
    elsif ( _service_has_chkservd_file($service) ) {
        return 1;
    }

    return undef;
}

1;

__END__
