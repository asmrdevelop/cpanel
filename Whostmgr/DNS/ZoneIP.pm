package Whostmgr::DNS::ZoneIP;

# cpanel - Whostmgr/DNS/ZoneIP.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::AcctUtils::DomainOwner::Tiny ();
use Whostmgr::AcctInfo::Owner            ();
use Whostmgr::ACLS                       ();
use Cpanel::Debug                        ();
use Try::Tiny;

my $locale;

sub changezoneip {    ## no critic qw(Subroutines::RequireArgUnpacking)
    my %OPTS;

    # sourceip    = the source ip to change from
    # destip      = the ip to change the source ip to
    # skipreload  = do not reload the nameserver
    # skipsync    = do not sync out the zones and just modify them in zoneref
    # zoneref     = hashref containing the zones to start with
    # domainref   = domainref containing a list of zones to process

    if ( ref $_[0] ) {
        %OPTS = %{ $_[0] };
    }
    else {
        %OPTS = @_;
    }

    my $source_ips = ref $OPTS{'sourceip'} ? $OPTS{'sourceip'} : [ $OPTS{'sourceip'} ];

    foreach my $source_ip (@$source_ips) {
        if ( $source_ip eq $OPTS{'destip'} ) {
            return 0, "changezoneip requires the “sourceip” and “destip” to be different: “$source_ip”";
        }
    }

    if ( !Whostmgr::ACLS::hasroot() ) {
        foreach my $domain ( @{ $OPTS{'domainref'} } ) {
            if ( !Whostmgr::AcctInfo::Owner::checkowner( $ENV{'REMOTE_USER'}, Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner($domain) ) ) {
                require Cpanel::Locale;
                $locale ||= Cpanel::Locale->get_handle();
                return ( 0, $locale->maketext( "Access Denied: You, “[_1]”, are not permitted to modify DNS for “[_2]”.", $ENV{'REMOTE_USER'}, $domain ) );
            }
        }
    }
    $OPTS{'showmsgs'} = 1;
    $OPTS{'sourceip'} = $source_ips;    # scripts::swapip accepts an array of ips

    require '/usr/local/cpanel/scripts/swapip';    ## no critic qw(Modules::RequireBarewordIncludes)
    my $ok = 1;
    my ( $output, @result );
    try {
        local *STDOUT;
        open( STDOUT, '>', \$output ) or die "Cannot save STDOUT: $!";
        @result = scripts::swapip->script( \%OPTS );
    }
    catch {
        $ok = 0;
        Cpanel::Debug::log_warn($_);
        $output ||= "$_";
    };

    return ( $ok, $output );
}

1;
