
# cpanel - Cpanel/RoR/Rewrites.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::RoR::Rewrites;

use strict;
use warnings;

use Cpanel::Debug                       ();
use Cpanel::Config::userdata::Constants ();
use Cpanel::DataStore                   ();

# Unlike most other functions here, this must be called by root.  This function
# does not allow changing the port since it does not fix up port assignments.
sub modify_rewrites {
    my ( $user, $old, $new ) = @_;
    my $rewrite = "$Cpanel::Config::userdata::Constants::USERDATA_DIR/$user/ruby-on-rails-rewrites.db";

    my $rorstore = Cpanel::DataStore::fetch_ref( $rewrite, 1 );
    if ( !$rorstore ) {
        return 1;    # Nothing to do.
    }

    foreach my $rewrite ( @{$rorstore} ) {
        if (   ( !exists $old->{'domain'} || $old->{'domain'} eq $rewrite->{'domain'} )
            && ( !exists $old->{'appname'}         || $old->{'appname'} eq $rewrite->{'appname'} )
            && ( !exists $old->{'rewritebasepath'} || $old->{'rewritebasepath'} eq $rewrite->{'rewritebasepath'} )
            && ( !exists $old->{'url'}             || $old->{'url'} eq $rewrite->{'url'} ) ) {

            for my $item (qw(domain appname rewritebasepath url)) {
                $rewrite->{$item} = $new->{$item} || $rewrite->{$item};
            }
        }
    }

    if ( !Cpanel::DataStore::store_ref( $rewrite, $rorstore ) ) {
        Cpanel::Debug::log_warn("Unable to write to file");
        return 0;
    }

    return 1;
}

1;
