package Cpanel::BandwidthDB::RootCache::Import;

# cpanel - Cpanel/BandwidthDB/RootCache/Import.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use experimental 'isa';

use Try::Tiny;

use Cpanel::Async::UserLock ();
use Cpanel::BandwidthDB     ();
use Cpanel::Config::Users   ();
use Cpanel::PromiseUtils    ();

#for tests
*_getcpusers = \&Cpanel::Config::Users::getcpusers;

#%opts can be:
#
#   before_start    - optional, coderef (receives arrayref of sorted usernames)
#   before_user     - optional, coderef (receives username)
#   after_user      - optional, coderef (receives username)
#   after_finish    - optional, coderef (receives arrayref of sorted usernames)
#
sub import_from_bandwidthdbs {
    my ( $cache_db, %opts ) = @_;

    my @users = sort( _getcpusers() );

    $opts{'before_start'}->( \@users ) if $opts{'before_start'};

    for my $user (@users) {
        $opts{'before_user'}->($user) if $opts{'before_user'};

        try {
            my $exists_lock = Cpanel::PromiseUtils::wait_anyevent(
                Cpanel::Async::UserLock::create_shared($user),
            )->get();

            my $bwdb = Cpanel::BandwidthDB::get_reader_for_root($user);
            $cache_db->import_from_bandwidthdb($bwdb);

            $opts{'after_user'}->($user) if $opts{'after_user'};
        }
        catch {

            # If the user went missing then it was probably just deleted
            # between the time when we created @users and now (which could
            # be fairly long for users with lots of bandwidth/domains).
            # Those aren’t worth warning on, so just ignore them.
            #
            if ( !( $_ isa Cpanel::Exception::UserNotFound ) ) {
                warn "Error while rebuilding cache for user “$user”: $_";
            }
        };
    }

    $opts{'after_finish'}->( \@users ) if $opts{'after_finish'};

    return;
}

1;
