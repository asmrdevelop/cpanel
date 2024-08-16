package Cpanel::Sys::Hostname::Modify;

# cpanel - Cpanel/Sys/Hostname/Modify.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

our $VERSION = '1.3';

my $logger;

use Cpanel::OS                  ();
use Cpanel::SafeRun::Simple     ();
use Cpanel::Sys::Hostname       ();
use Cpanel::Sys::Uname          ();
use Cpanel::Sys::Hostname::FQDN ();

#
#
# Helper routine for changing config files in subroutine below.
#
# Given a filename and a coderef that modifies the value of $_, This routine
# reads the file, executes the coderef and rewrites the file. It handles the
# grunt work of the file manipulation, protecting $_, and handling exceptions
# in the case that any happen.
#
sub _replace_file_content ( $conf_file, $coderef ) {

    if ( -f $conf_file && open( my $fh, '+<', $conf_file ) ) {
        local $/;
        local $_ = <$fh>;
        local $SIG{'__DIE__'} = 'DEFAULT';    # protection from global sigDIE handler.
        eval {
            my $content = $coderef->($_);
            seek( $fh, 0, 0 );
            print {$fh} $content;
            truncate( $fh, tell($fh) );
            1;
        } or do {
            _logger()->warn("Failed to update '$conf_file': $@");
            return;
        };
    }
    else {
        my $error = $! // '';
        _logger()->warn("Unable to change current host name in '$conf_file' $error");
        return;
    }
    return 1;
}

################################################################################
# _get_host_domain_name_from_file  determine host/domain names from
# configuration files typically in /etc. This sub is called from gethostname
# and returns domainname.
################################################################################
sub _set_host_name_in_config_file ($new_host_name) {

    my $sysconfig_network = Cpanel::OS::sysconfig_network();

    if ( !$sysconfig_network ) {
        _logger()->warn( "Skip _set_host_name_in_config_file on distro " . Cpanel::OS::display_name() );
        return;
    }

    return _replace_file_content(
        $sysconfig_network,
        sub ($str) {
            unless ( $str =~ s/^\s*HOSTNAME\s*=.*?$/HOSTNAME=$new_host_name/m ) {
                $str .= "HOSTNAME=$new_host_name\n";
            }
            return $str;
        }
    );
}

#
#
sub make_hostname_lowercase_fqdn {
    if ( $< != 0 ) {
        _logger()->warn("Only root can change the host name");
        return;
    }

    my $hostname = Cpanel::Sys::Hostname::FQDN::get_fqdn_hostname();

    # This always returns lowercase
    if ( !defined $hostname || !length $hostname ) {
        _logger()->warn("Unable to retrieve current hostname");
        return;
    }

    my $hostname_from_uname = ( Cpanel::Sys::Uname::get_uname_cached() )[1];

    # This may return uppercase

    if ( $hostname_from_uname && $hostname eq $hostname_from_uname ) {

        # Return if the name is currently all lowercase
        # and it matches the uname hostname
        return 1;
    }

    return _set_hostname($hostname);
}

sub _set_hostname {
    my ($hostname) = @_;
    if ( _set_host_name_in_config_file($hostname) ) {
        Cpanel::SafeRun::Simple::saferun( '/bin/hostname', $hostname );
    }

    # Clear the cache
    $Cpanel::Sys::Hostname::cachedhostname = '';
    Cpanel::Sys::Uname::clearcache();
    return 1;
}

sub _logger {
    require Cpanel::Logger;
    $logger ||= Cpanel::Logger->new();
    return $logger;
}

1;
