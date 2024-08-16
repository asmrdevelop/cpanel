package Cpanel::MysqlUtils::Secure;

#                                      Copyright 2024 WebPros International, LLC
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited.

use cPstrict;

use Cpanel::Database        ();
use Cpanel::Mysql::Flush    ();
use Cpanel::MysqlUtils::Dir ();
use Cpanel::SafeRun::Simple ();

=encoding utf-8

=head1 NAME

Cpanel::MysqlUtils::Secure - Run various security actions on the mysql server

=head1 SYNOPSIS

    use Cpanel::MysqlUtils::Secure;

    my $dbh = Cpanel::MysqlUtils::Connect::get_dbi_handle();
    my $verbose = 1;

    Cpanel::MysqlUtils::Secure::perform_secure_actions($dbh, {
        'securemycnf' => 1,
        'chowndatadir' => 1,
    },
    $verbose);

=cut

my @ordered_known_actions = qw(
  securemycnf
  chowndatadir
  removeanon
  removeremoteroot
  removelockntmp
  removetestdb
  removepublicgrants
);

=head2 perform_secure_actions($dbh, $actions_to_perform_hr, $verbose)

Perform named actions in order to secure the local mysql server.

See @ordered_known_actions in this module for a list of known
actions.

=over 2

=item Input

=over 3

=item $dbh C<OBJECT>

    A MySQL DBI handle

=item $actions_to_perform_hr C<HASHREF>

    A hashref of known actions to perform

    Example:
    {
        'securemycnf' => 1,
        'chowndatadir' => 1,
    }

=item $verbose C<SCALAR>

    If $verbose is a truthy value, this function
    will print status of each security action.

=back

=item Output

This function always return 1 on success or dies
on failure.

=back

=cut

sub perform_secure_actions ( $dbh, $actions_to_perform_hr, $verbose = undef ) {    ## no critic (Subroutines::ProhibitManyArgs)
    return 1 if ( -e '/etc/securemysqldisable' || -e '/etc/mysqldisable' );

    my $db_obj = Cpanel::Database->new( { 'reset' => 1 } );

    my %known_actions_h = map { $_ => 1 } @ordered_known_actions;
    for my $requested_action ( sort( keys( $actions_to_perform_hr->%* ) ) ) {
        unless ( $known_actions_h{$requested_action} ) {
            die "perform_secure_actions does not know how to perform the “$requested_action” action.";
        }
    }

    for my $action (@ordered_known_actions) {
        next unless $actions_to_perform_hr->{$action};
        my $sub = "_perform_$action";
        local $@;
        eval { __PACKAGE__->$sub( $dbh, $verbose, $db_obj ); };
        warn if $@;
    }

    print "Flushing privileges table ... " if $verbose;
    Cpanel::Mysql::Flush::flushprivs();
    print "Done.\n" if $verbose;

    return 1;
}

sub _perform_securemycnf ( $self, $dbh, $verbose, $db_obj ) {
    my $mysqlrootcnf = '/root/.my.cnf';
    my ( $mode, $uid, $gid ) = ( stat($mysqlrootcnf) )[ 2, 4, 5 ];

    # Ensure /root/.my.cnf perms
    if ( defined $mode ) {
        chown 0, 0, $mysqlrootcnf if $uid != 0 || $gid != 0;
        chmod 0600, $mysqlrootcnf if $mode & 07777 != 0600;
    }
    return;
}

sub _perform_chowndatadir ( $self, $dbh, $verbose, $db_obj ) {

    # Set db ownership
    my $mysqldatadir = Cpanel::MysqlUtils::Dir::getmysqldir();

    # TODO: This is relocated code and should be refactored to use
    # Cpanel::SafeRun::Object
    if ( -d $mysqldatadir ) {
        my $out = Cpanel::SafeRun::Simple::saferun( '/bin/chown', '-R', 'mysql', '--', $mysqldatadir );
        print $out if $verbose;
    }
    return;
}

sub _perform_removeanon ( $self, $dbh, $verbose, $db_obj ) {
    print "Removing anonymous users ... " if $verbose;
    my $users = $db_obj->search_mysqlusers(q{User=''});
    my $sql   = $db_obj->get_remove_users_sql($users);

    if ($sql) {
        eval { $dbh->do($sql); };
        if ( _dropped_nonexistent_user_error($@) ) {
            for my $user ( $users->@* ) {
                $db_obj->remove_user_from_global_priv( $user->%* );
            }
        }
    }

    print "Done\n" if $verbose;
    return;
}

sub _perform_removeremoteroot ( $self, $dbh, $verbose, $db_obj ) {
    print "Removing remote root login ... " if $verbose;
    my $users = $db_obj->search_mysqlusers(q{User='root' AND Host!='localhost'});
    my $sql   = $db_obj->get_remove_users_sql($users);

    if ($sql) {
        eval { $dbh->do($sql); };
        if ( _dropped_nonexistent_user_error($@) ) {
            $db_obj->remove_user_from_global_priv( $_->%* ) for $users->@*;
        }
    }

    print "Done\n" if $verbose;
    return;
}

sub _perform_removelockntmp ( $self, $dbh, $verbose, $db_obj ) {
    print "Dropping global lock tables and create tmp tables permissions ... " if $verbose;
    $db_obj->revoke_privs( 'user' => $_->{'user'}, 'host' => $_->{'host'}, 'on' => '*.*', 'privs' => [ 'LOCK TABLES', 'CREATE TEMPORARY TABLES' ] ) for $db_obj->search_mysqlusers(q{User!='root'})->@*;
    print "Done\n" if $verbose;
    return;
}

sub _perform_removetestdb ( $self, $dbh, $verbose, $db_obj ) {
    print "Removing all privileges for test db ... " if $verbose;
    $dbh->do(qq{DELETE FROM mysql.db WHERE Db LIKE 'test%' AND User='';});
    print "Done\n"                     if $verbose;
    print "Dropping test database... " if $verbose;
    local $@;
    eval { $dbh->do(qq{DROP DATABASE IF EXISTS test;}); };

    # if the test db is not failure is ok
    print "Done\n" if $verbose;

    return;
}

sub _perform_removepublicgrants ( $self, $dbh, $verbose, $db_obj ) {
    return unless $db_obj->has_public_grants;
    print "Removing all default public grants for test databases ... " if $verbose;
    $db_obj->revoke_default_public_grants($dbh);
    print "Done\n" if $verbose;
    return;
}

sub _dropped_nonexistent_user_error ($error) {
    if ($error) {
        require Cpanel::Mysql::Error;
        unless ( $error->get('error_code') == Cpanel::Mysql::Error::ER_CANNOT_USER() ) {
            warn "MySQL Error: $error\n";
            return 0;
        }
        return 1;
    }
    return 0;
}

1;
