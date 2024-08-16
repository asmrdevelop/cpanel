package Cpanel::AcctUtils::Owner;

# cpanel - Cpanel/AcctUtils/Owner.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::AcctUtils::Lookup::Webmail ();
use Cpanel::Config::LoadCpUserFile     ();
use Cpanel::Config::HasCpUserFile      ();
use Cpanel::LoadModule                 ();
use Cpanel::Debug                      ();
use Try::Tiny;

my $USEROWNER_CACHE_ref;
our $CACHE_IS_SET  = 0;
our $DEFAULT_OWNER = 'root';

# CACHING: We must only cache positive hits, we should never
# cache if the user does not exist.
sub getowner {
    my ($user) = @_;

    if ( !$user ) {
        Cpanel::Debug::log_warn('No user specified');
        return;
    }
    elsif ( $user eq 'root' || $user eq 'nobody' || $user eq 'cpanel' ) {
        return $DEFAULT_OWNER;
    }

    if ( Cpanel::AcctUtils::Lookup::Webmail::is_strict_webmail_user($user) ) {
        my $err;
        try {
            # Handle webmail accounts
            Cpanel::LoadModule::load_perl_module('Cpanel::AcctUtils::Lookup');
            $user = Cpanel::AcctUtils::Lookup::get_system_user($user);
        }
        catch {
            $err = $_;
        };

        # Legacy behavior is to return '' if the system user does not exist
        return '' if !$user || $err;
    }

    if ( !$CACHE_IS_SET && !-r '/var/cpanel/users/' . $user ) {

        # Prime the trueuserowners cache when it's not already loaded and we can't read the cpuser file
        build_trueuserowners_cache();
    }

    if ( $USEROWNER_CACHE_ref->{$user} ) {
        return $USEROWNER_CACHE_ref->{$user};
    }
    elsif ( !Cpanel::Config::HasCpUserFile::has_readable_cpuser_file($user) ) {
        return $DEFAULT_OWNER;
    }

    # Untaint username.
    $user = $1 if $user =~ /^([\w.-]+)$/;

    my $cpuser_ref = Cpanel::Config::LoadCpUserFile::loadcpuserfile($user);

    if ($cpuser_ref) {
        if ( $cpuser_ref->{'OWNER'} ) {
            return ( $USEROWNER_CACHE_ref->{$user} = $cpuser_ref->{'OWNER'} );
        }

        # This is a unique case where we want to cache
        # since this is not a negitive cache, its just
        # a broken cpanel users file.   The user
        # does exist and is owned by root but its just
        # missing the OWNER= line
        return ( $USEROWNER_CACHE_ref->{$user} = $DEFAULT_OWNER );
    }

    # Note: Cpanel::Userdomains::updateuserdomains calls clearcache()
    # to ensure this does not break for newly created users

    return $DEFAULT_OWNER;
}

sub build_trueuserowners_cache {
    local $@;
    eval 'require Cpanel::Config::LoadConfig';    ## no critic qw(ProhibitStringyEval)
    die "Failed to load Cpanel::Config::LoadConfig: $@" if $@;
    $CACHE_IS_SET        = 1;
    $USEROWNER_CACHE_ref = Cpanel::Config::LoadConfig::loadConfig( $Cpanel::ConfigFiles::TRUEUSEROWNERS_FILE, undef, ': ' );
    return 1;
}

sub clearcache {
    $CACHE_IS_SET        = 0;
    $USEROWNER_CACHE_ref = undef;
    return;
}

1;
