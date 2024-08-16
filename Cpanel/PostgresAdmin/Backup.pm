package Cpanel::PostgresAdmin::Backup;

# cpanel - Cpanel/PostgresAdmin/Backup.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::PostgresAdmin::Check ();
use Cpanel::Alarm                ();

our $TIMEOUT = 10800;

=encoding utf-8

=head1 NAME

Cpanel::PostgresAdmin::Backup - Backup postgresql for a user

=head1 SYNOPSIS

    use Cpanel::PostgresAdmin::Backup ();

    my $backup_text_sr = Cpanel::PostgresAdmin::Backup::fetch_backup_as_sr($postgresadmin_handle);
    my $backup_text_hr = Cpanel::PostgresAdmin::Backup::fetch_backup_as_hr($postgresadmin_handle);

=head2 fetch_backup_as_sr($postgresadmin_handle)

Create a backup of a user's postgresql configuration
including: database names, database users, and
grants.

The backup is intended to be consumed by pkgacct.

This function returns a scalar reference of the backup
text.

=over 2

=item Input

=over 3

=item $postgresadmin_handle C<OBJECT>

    A Cpanel::PostgresAdmin or Cpanel::PostgresAdmin::Basic object

=back

=back

=cut

sub fetch_backup_as_sr {
    my ($postgresadmin_handle) = @_;

    my $backup_text = '';

    # allow more time for dumpsql to run
    my $alarm = Cpanel::Alarm->new( $TIMEOUT, sub { die "Timeout while running fetch_backup_as_sr" } );

    my $ping = Cpanel::PostgresAdmin::Check::ping();
    chomp($ping);

    #no pgdatacheck needed
    $backup_text .= "-- cPanel BEGIN PING\n";
    $backup_text .= $ping . "\n";
    $backup_text .= "-- cPanel END PING\n";

    if ( $ping =~ /pong/i ) {
        $backup_text .= "-- cPanel BEGIN LISTDBS\n";
        my @dbs = $postgresadmin_handle->listdbs();
        $backup_text .= join( "\n", @dbs );
        $backup_text .= "\n" if @dbs;
        $backup_text .= "-- cPanel END LISTDBS\n";
        $backup_text .= "-- cPanel BEGIN DUMPSQL_USERS\n";
        $backup_text .= join( '', @{ $postgresadmin_handle->fetchsql_users() } );
        $backup_text .= "-- cPanel END DUMPSQL_USERS\n";
        $backup_text .= "-- cPanel BEGIN DUMPSQL_GRANTS\n";
        $backup_text .= join( '', @{ $postgresadmin_handle->fetchsql_grants() } );
        $backup_text .= "-- cPanel END DUMPSQL_GRANTS\n";
    }

    return \$backup_text;
}

=head2 fetch_backup_as_hr($postgresadmin_handle)

Create a backup of a user's postgresql configuration
including: database names, database users, and
grants.

The backup is intended to be consumed by pkgacct.

This function returns a hash reference of the backup
data.

=over 2

=item Input

=over 3

=item $postgresadmin_handle C<OBJECT>

    A Cpanel::PostgresAdmin or Cpanel::PostgresAdmin::Basic object

=back

=back

=cut

sub fetch_backup_as_hr {
    my ($postgresadmin_handle) = @_;

    my $backup_text = '';

    # allow more time for dumpsql to run
    my $alarm = Cpanel::Alarm->new( $TIMEOUT, sub { die "Timeout while running fetch_backup_as_hr" } );

    my $ping = Cpanel::PostgresAdmin::Check::ping();
    chomp($ping);

    my %backup = ( PING => $ping );

    if ( $ping =~ /pong/i ) {
        my @dbs = $postgresadmin_handle->listdbs();
        $backup{LISTDBS}        = \@dbs;
        $backup{DUMPSQL_USERS}  = $postgresadmin_handle->fetchsql_users();
        $backup{DUMPSQL_GRANTS} = $postgresadmin_handle->fetchsql_grants();
    }

    return \%backup;
}

1;
