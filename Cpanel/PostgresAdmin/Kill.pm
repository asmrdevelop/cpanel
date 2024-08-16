package Cpanel::PostgresAdmin::Kill;

# cpanel - Cpanel/PostgresAdmin/Kill.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::DB::Reserved         ();
use Cpanel::Debug                ();
use Cpanel::PostgresAdmin        ();
use Cpanel::PostgresAdmin::Check ();
use Try::Tiny;

sub remove_postgres_assets_for_cpuser {
    my ($user) = @_;
    if ( Cpanel::PostgresAdmin::Check::is_configured()->{'status'} ) {

        #There have been cases where administrators manually put "root" as a DBuser
        #inside a DB map file; if the admin then deletes the map file's user,
        #we need not to drop the "root@localhost" postgresql user.

        my @DBUSERS_NEVER_TO_DROP = Cpanel::DB::Reserved::get_reserved_usernames();
        my $postgres_admin        = Cpanel::PostgresAdmin->new( { 'cpuser' => $user } );

        if ( !$postgres_admin ) {
            die <<END;
If this account had a postgresql user associated with it, you will need to
manually remove that user once the postgresql server is reachable again.

END
        }

        my @users = $postgres_admin->listusers();
        my @dbs   = $postgres_admin->listdbs();

        foreach my $db (@dbs) {
            try {
                $postgres_admin->drop_db($db);
            }
            catch {
                Cpanel::Debug::log_warn($_);
            };

        }

        # The main user may not exist because our
        # tests do not create a postgres user.
        #
        # This generated a warning during account removal
        # so we now check to see if the user exists before
        # trying to remove it.
        push @users, $user if $postgres_admin->user_exists($user);

        foreach my $db_user (@users) {

            #See note above.
            next if grep { $_ eq $db_user } @DBUSERS_NEVER_TO_DROP;

            try {
                $postgres_admin->deluser( $db_user, $Cpanel::PostgresAdmin::SKIP_OWNER_CHECK );
            }
            catch {
                Cpanel::Debug::log_warn($_);
            };
        }
    }

    return 1;
}
1;
