package Cpanel::Mysql::Kill;

# cpanel - Cpanel/Mysql/Kill.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::DB::Reserved ();
use Cpanel::DB::Utils    ();
use Cpanel::Mysql::Basic ();
use Cpanel::Mysql::Flush ();

=pod

=head1 NAME

Cpanel::Mysql::Kill

=head1 SYNOPSIS

  my $kill_ok = Cpanel::Mysql::Kill::killmysqluserprivs('bob');

=head2 killmysqluserprivs( USER )

Remove MySQL privileges from from a user

=head3 Arguments

USER -  The user to remove MySQL privileges from

=head3 Return Value

This function always returns 1 unless an exception is generated

=cut

sub killmysqluserprivs {
    my ($user) = @_;
    die 'No user specified' if !$user;

    my $mysql = Cpanel::Mysql::Basic->new( { 'cpuser' => $user } );

    if ( !$mysql ) {
        die <<END;
If this account had a MySQL user associated with it, you will need to
manually remove that user once the MySQL server is reachable again.

This may be done by running:

  /usr/local/cpanel/scripts/killmysqluserprivs $user

END
    }

    #There have been cases where administrators manually put "root" as a DBuser
    #inside a DB map file; if the admin then deletes the map file's user,
    #we need not to drop the "root@localhost" MySQL user.
    my @DBUSERS_NEVER_TO_DROP = Cpanel::DB::Reserved::get_reserved_usernames();

    my $owner = Cpanel::DB::Utils::username_to_dbowner($user);
    my @users = $mysql->listusers();

    foreach my $db_user ( $owner, @users ) {

        #See note above.
        next if grep { $_ eq $db_user } @DBUSERS_NEVER_TO_DROP;

        #TODO: Replace these with Cpanel::MysqlUtils::Grants::Users::drop_user_in_mysql()
        $mysql->sendmysql( "DELETE FROM user WHERE user=?;",         {}, $db_user );
        $mysql->sendmysql( "DELETE FROM db WHERE user=?;",           {}, $db_user );
        $mysql->sendmysql( "DELETE FROM tables_priv WHERE user=?;",  {}, $db_user );
        $mysql->sendmysql( "DELETE FROM columns_priv WHERE user=?;", {}, $db_user );
        $mysql->sendmysql( "DELETE FROM procs_priv WHERE user=?;",   {}, $db_user );
    }

    require Cpanel::Mysql::Remote::Notes;
    my $notes_obj = Cpanel::Mysql::Remote::Notes->new(
        username => $user,
    );
    $notes_obj->delete_all();

    Cpanel::Mysql::Flush::flushprivs();
    return 1;
}

1;
