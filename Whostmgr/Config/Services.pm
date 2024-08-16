package Whostmgr::Config::Services;

# cpanel - Whostmgr/Config/Services.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Debug ();

# stolen from Cpanel::PHPFPM::Controller to avoid useless dependencies
sub get_phpfpm_versions {
    my @versions;
    if ( opendir( my $optcpanel_dh, ${Cpanel::PHPFPM::Constants::opt_cpanel} ) ) {
        my @files = readdir($optcpanel_dh);
        foreach my $file (@files) {
            if ( index( $file, 'ea-php' ) > -1 && $file =~ m/ea\-php(\d{2})/ ) {
                if ( -f ${Cpanel::PHPFPM::Constants::opt_cpanel} . '/' . $file . '/root/etc/php-fpm.conf' ) {
                    push( @versions, $1 );
                }
            }
        }
        closedir($optcpanel_dh);
    }
    return \@versions;
}

sub _check_fpm_enablement {

    require Cpanel::PHPFPM::Constants;

    # we would like to use Cpanel::PHPFPM::Controller::get_phpfpm_versions without the deps
    # for now provide a local version of it
    my $php_versions = get_phpfpm_versions();
    foreach my $version (@$php_versions) {
        my $path = "$Cpanel::PHPFPM::Constants::opt_cpanel/ea-php$version/root/usr/sbin/php-fpm";
        return 1 if -x $path;
    }
    return 0;
}

sub _legacy_backups_available {
    require Cpanel::Backup::Status;
    return Cpanel::Backup::Status::is_legacy_backup_enabled();
}

######[ get list of services that are enabled ]####################################################

# rules to check if a service is enabled, by default use Cpanel::Services::Enabled::is_enabled
# Exposed for testing
our $services_check = {
    exim   => 'exim',
    sshd   => 'sshd',
    tomcat => sub {
        return 1 if -e "/usr/local/cpanel/scripts/ea-tomcat85";
        require Cpanel::Services::Enabled;
        return Cpanel::Services::Enabled::is_enabled('tomcat');    # exception
    },
    mysql          => 'mysql',
    dns            => [qw(bind named dns)],
    httpd          => [qw(http httpd apache)],
    httpd_fpm      => sub { _check_fpm_enablement() },
    legacy_backups => sub { _legacy_backups_available() },
    imap           => [qw(cpimap imap imapd)],
    postgres       => [qw(postgresql postgres postmaster)],
    ftp            => [qw(ftpd ftpserver)],
};

sub get_enabled {
    my ( $whmvar_ref, $only_check ) = @_;
    if ( !defined $whmvar_ref ) {
        $whmvar_ref = {};
    }
    elsif ( ref $whmvar_ref ne 'HASH' ) {
        Cpanel::Debug::log_warn("Invalid usage. Hash reference expected.");
        return;
    }

    foreach my $service ( sort keys %$services_check ) {
        my $key = $service . '_enabled';
        next if defined $only_check && $only_check ne $key;
        if ( ref $services_check->{$service} eq 'CODE' ) {
            $whmvar_ref->{$key} = $services_check->{$service}->();
        }
        elsif ( ref $services_check->{$service} eq 'ARRAY' ) {
            require Cpanel::Services::Enabled;
            $whmvar_ref->{$key} = Cpanel::Services::Enabled::are_enabled( { match => 'any', services => $services_check->{$service} } );
        }
        else {    # default behavior
            require Cpanel::Services::Enabled;
            $whmvar_ref->{$key} = Cpanel::Services::Enabled::is_enabled( $services_check->{$service} );
        }
    }

    return wantarray ? %{$whmvar_ref} : $whmvar_ref;
}

1;
