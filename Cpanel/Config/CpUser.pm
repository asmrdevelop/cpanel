package Cpanel::Config::CpUser;

# cpanel - Cpanel/Config/CpUser.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Debug                        ();
use Cpanel::LoadModule                   ();
use Cpanel::Config::LoadUserDomains      ();
use Cpanel::Config::LoadCpUserFile       ();
use Cpanel::ConfigFiles                  ();
use Cpanel::FileUtils::Write::JSON::Lazy ();

#TODO: This module should be the only one that cares about the actual
#filesystem path for the cpuser files. Other code should query this module
#(and/or LoadCpUserFile) for everything related to the cpuser datastore.
our $cpuser_dir;
*cpuser_dir = \$Cpanel::ConfigFiles::cpanel_users;
our $cpuser_cache_dir = "$cpuser_dir.cache";

our $header = <<END;
# cPanel -- If you edit this file directly you must run /usr/local/cpanel/scripts/updateuserdomains afterwards to rebuild the system caches.
# If you edit MAX_EMAIL_PER_HOUR or MAX_EMAIL_PER_HOUR-[domain] you must run /usr/local/cpanel/scripts/updateuserdomains'
END

#Array in memory => "$key$num" on disk, e.g.:
#DOMAINS becomes DNS1, DNS2, etc.
my %memory_file_list_key = qw(
  DOMAINS         DNS
  DEADDOMAINS     XDNS
  HOMEDIRLINKS    HOMEDIRPATHS
);

sub clean_cpuser_hash {
    my ( $cpuser_ref, $user ) = @_;

    {
        my @missing = grep { !exists $cpuser_ref->{$_} } required_cpuser_keys();
        if (@missing) {
            $user = q{} if !defined $user;
            Cpanel::Debug::log_warn( "The following keys are missing from supplied '$user' cPanel user data: " . join( ', ', @missing ) . ", to prevent data loss, the data was not saved." );
            return;
        }
    }

    if ( grep { $_ && index( $_, "\n" ) != -1 } %$cpuser_ref ) {

        # Nothing good can come of this.
        Cpanel::Debug::log_warn("The cpuser data contains newlines.  This is not allowed as it would corrupt the file.");
        return;
    }

    ## DOMAIN
    # Special value that needs to be fixed up
    my $domain = $cpuser_ref->{'DOMAIN'};
    if ( !$domain ) {    # Try to lookup main domain in /etc/trueuserdomains
        my $trueuserdomains_ref = Cpanel::Config::LoadUserDomains::loadtrueuserdomains( undef, 1 );
        $domain = $trueuserdomains_ref->{$user} || '';
        if ( !$domain ) {
            Cpanel::Debug::log_info("Unable to determine user ${user}'s main domain");
        }
    }

    my %clean_data = (
        %$cpuser_ref,
        DNS => $domain,
    );

    delete @clean_data{
        q{},
        'DOMAIN',
        'DBOWNER',
        '__CACHE_DATA_VERSION',
        ( keys %memory_file_list_key ),
    };

    # Clean up this value if it got misserialized.
    if ( defined $clean_data{'DISK_BLOCK_LIMIT'} && $clean_data{'DISK_BLOCK_LIMIT'} eq 'unlimited' ) {
        $clean_data{'DISK_BLOCK_LIMIT'} = 0;
    }

    #DOMAINS => DNS1, DNS2, etc.
    while ( my ( $memkey, $filekey ) = each %memory_file_list_key ) {
        if ( exists $cpuser_ref->{$memkey} && scalar @{ $cpuser_ref->{$memkey} } ) {
            my $doms_ar = $cpuser_ref->{$memkey};
            my $count   = 0;
            @clean_data{ ( map { $filekey . ++$count } @$doms_ar ) } = @$doms_ar;
        }
    }

    #To keep the HOMEDIRPATHS key in place, rather than HOMEDIRPATHS1.
    #This simplifies backward compatibility when accounts are backed up.
    my $homedirs_key_in_file = $memory_file_list_key{'HOMEDIRLINKS'};
    if ( exists $clean_data{ $homedirs_key_in_file . 1 } ) {
        $clean_data{$homedirs_key_in_file} = delete $clean_data{ $homedirs_key_in_file . 1 };
    }

    return wantarray ? %clean_data : \%clean_data;
}

sub get_cpgid {
    my ($user) = @_;

    # Calculate user GID for the group ownership of the file
    my $cpgid = 0;

    if ( exists $INC{'Cpanel/PwCache.pm'} || Cpanel::LoadModule::load_perl_module('Cpanel::PwCache') ) {
        $cpgid = ( Cpanel::PwCache::getpwnam_noshadow($user) )[3];
    }

    return $cpgid;
}

sub recache {
    my ( $cpuser_ref, $user, $cpgid ) = @_;

    my $user_cache_file = $cpuser_cache_dir . '/' . $user;

    # Recache updated file if Cpanel::FileUtils::Write::JSON::Lazy is available
    Cpanel::Config::LoadCpUserFile::create_users_cache_dir();
    $cpuser_ref->{'__CACHE_DATA_VERSION'} = $Cpanel::Config::LoadCpUserFile::VERSION;    # set this before the cache is written so that it will be included in the cache

    if ( Cpanel::FileUtils::Write::JSON::Lazy::write_file( $user_cache_file, $cpuser_ref, 0640 ) ) {
        chown 0, $cpgid, $user_cache_file if $cpgid;                                     # this is ok if the chown happens after as we fall though to reading the non-cache on a failed open
    }
    else {
        unlink $user_cache_file;                                                         #outdated
    }
}

sub required_cpuser_keys {
    my @keys = qw( FEATURELIST HASCGI MAXSUB MAXADDON DEMO RS USER MAXFTP MAXLST MAXPARK STARTDATE BWLIMIT IP MAXSQL DOMAIN MAXPOP PLAN OWNER );

    return wantarray ? @keys : \@keys;
}

1;
