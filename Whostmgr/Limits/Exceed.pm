package Whostmgr::Limits::Exceed;

# cpanel - Whostmgr/Limits/Exceed.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Whostmgr::ACLS              ();
use Whostmgr::Limits::Resellers ();
use Whostmgr::Resellers::Stat   ();

my %LIMIT_NAMES = (
    'bw'   => 'bandwidth',
    'disk' => 'disk space',
);

sub would_exceed_limit {
    my $limit  = shift;
    my $op_ref = shift;
    if ( Whostmgr::ACLS::hasroot() ) {
        return ( 0, "Limit is within allowed allocation" );
    }
    my $user            = $op_ref->{'user'};
    my $newlimit        = $op_ref->{'newlimit'} ? int( abs( $op_ref->{'newlimit'} ) ) : 0;
    my $reseller_limits = Whostmgr::Limits::Resellers::load_resellers_limits();

    my $resources = $reseller_limits->{'limits'}->{'resources'};

    if ( $resources->{'enabled'} ) {

        if ( $op_ref->{'nounlimited'} && int($newlimit) < 1 ) {
            return ( 1, "You do not have permission to grant unlimited $LIMIT_NAMES{$limit} usage." );
        }

        my $overselling = $resources->{'overselling'}->{'type'}->{$limit};
        my $the_limit   = $resources->{'type'}->{$limit};

        my ( $used, $remain );

        #These totals are exclusive of $user.
        my ( $totaldiskused, $totalbwused, $totaldiskalloc, $totalbwalloc ) = Whostmgr::Resellers::Stat::statres( 1, $user );

        if ($overselling) {
            $used = ( $limit eq 'bw' ? $totalbwused : $totaldiskused );
        }
        else {
            $used = ( $limit eq 'bw' ? $totalbwalloc : $totaldiskalloc );
        }
        $remain = ( ( $the_limit || 0 ) - ( $used || 0 ) );

        if ( $overselling ? ( $remain < 0 ) : ( $remain < $newlimit ) ) {
            my $rs_error = ucfirst( $LIMIT_NAMES{$limit} ) . ' modification failed: ';
            if ( $remain > 0 ) {
                $rs_error .= "You only have $remain megabytes remaining, and this account modification requires $newlimit megabytes.";
                if ($overselling) {
                    $rs_error .= "(Total $LIMIT_NAMES{$limit} used: $used; Your limit: $the_limit)";
                }
            }
            else {
                my $abslimit = abs($remain);
                $rs_error .= " You have exceeded your $LIMIT_NAMES{$limit} allotment by $abslimit megabytes!";
            }
            return ( 1, $rs_error );
        }
    }
    return ( 0, "Limit is within allowed allocation" );
}
