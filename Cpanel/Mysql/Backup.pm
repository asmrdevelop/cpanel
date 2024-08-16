package Cpanel::Mysql::Backup;

# cpanel - Cpanel/Mysql/Backup.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::Constants::MySQL ();
use Cpanel::Config::LoadCpConf       ();
use Cpanel::Alarm                    ();
use Try::Tiny;

=encoding utf-8

=head1 NAME

Cpanel::Mysql::Backup - Backup mysql for a user

=head1 SYNOPSIS

    use Cpanel::Mysql::Backup ();

    my $backup_text_sr = Cpanel::Mysql::Backup::fetch_backup_as_sr($mysql_handle, $cpconf, $domains_ar);
    my $backup_text_hr = Cpanel::Mysql::Backup::fetch_backup_as_hr($mysql_handle, $cpconf, $domains_ar);

=head2 fetch_backup_as_sr($mysql_handle, $cpconf, $domains_ar)

Create a backup of a user's mysql configuration
including: database names, database users, grants,
and roundcube ids (if applicable).

The backup is intended to be consumed by pkgacct.

This function returns a scalar reference of the backup
text.

=over 2

=item Input

=over 3

=item $mysql_handle C<OBJECT>

    A Cpanel::Mysql or Cpanel::Mysql::Basic object

=item $cpconf C<HASHREF>

    cpanel configuration from
    Cpanel::Config::LoadCpConf::loadcpconf*

=item $domains_ar C<ARRAYREF>

    An arrayref of domains that the user
    controls.

=back

=back

=cut

sub fetch_backup_as_sr {
    my ( $mysql_handle, $cpconf, $domains_ar ) = @_;
    die "Need domains!" if !@$domains_ar;

    $cpconf ||= Cpanel::Config::LoadCpConf::loadcpconf_not_copy();

    my $backup_text = '';
    $backup_text .= "-- cPanel BEGIN ALIVE\n";
    $backup_text .= "ALIVE\n";
    $backup_text .= "-- cPanel END ALIVE\n";

    # allow more time for dumpsql to run
    my $alarm = Cpanel::Alarm->new( $Cpanel::Config::Constants::MySQL::TIMEOUT_MYSQLDUMP, sub { die "Timeout while running fetch_backup_as_sr" } );

    my @SYSTEMDBS = ('mysql');
    if ( exists $cpconf->{'roundcube_db'} && $cpconf->{'roundcube_db'} eq 'sqlite' ) {

        #sqllite handles roundcube
    }
    else {
        push @SYSTEMDBS, 'roundcube';
    }

    $backup_text .= "-- cPanel BEGIN LISTDBS\n";
    my @dbs = $mysql_handle->listdbs();
    $backup_text .= join( "\n", @dbs );
    $backup_text .= "\n" if @dbs;
    $backup_text .= "-- cPanel END LISTDBS\n";
    $backup_text .= "-- cPanel BEGIN LASTUPDATETIMES\n";
    $backup_text .= join( "\n", map { $_ . '=' . $mysql_handle->last_update_time($_) } ( @SYSTEMDBS, @dbs ) );
    $backup_text .= "\n" if @dbs || @SYSTEMDBS;
    $backup_text .= "-- cPanel END LASTUPDATETIMES\n";
    $backup_text .= "-- cPanel BEGIN DUMPSQL\n";
    my $grants_ar = $mysql_handle->fetch_grants();

    if ( $grants_ar && @$grants_ar ) {
        $backup_text .= join( '', @$grants_ar );
    }
    $backup_text .= "-- cPanel END DUMPSQL\n";

    if ( grep( /roundcube/, @SYSTEMDBS ) && $mysql_handle->{'hasmysqlso'} ) {
        my $user = $mysql_handle->{'cpuser'};

        # if we change this here, we must change it in pkgacct as well -- changed to use the same logic in to be merged case 40362
        my $sql_dnslist = join( ',', map { $mysql_handle->{'dbh'}->quote($_) } grep { index( $_, '*' ) == -1 } @$domains_ar );
## case 16846: adding "username = '$user'" to ensure the system users that use webmail are converted
        my $ids_ref;
        try {
            my $query = "SELECT user_id FROM roundcube.users WHERE BINARY username = ? OR BINARY SUBSTRING_INDEX(username,'\@',-1) IN (${sql_dnslist});";
            $ids_ref = $mysql_handle->{'dbh'}->selectall_arrayref( $query, undef, $user );
        }
        catch {
            local $@ = $_;
            warn;
        };
        $backup_text .= "-- cPanel BEGIN ROUNDCUBEIDS\n";
        $backup_text .= join( ',', map { $_->[0] } @$ids_ref ) . "\n" if ref $ids_ref && @$ids_ref;
        $backup_text .= "-- cPanel END ROUNDCUBEIDS\n";
    }
    return \$backup_text;
}

=head2 fetch_backup_as_hr($mysql_handle, $cpconf, $domains_ar)

Create a backup of a user's mysql configuration
including: database names, database users, grants,
and roundcube ids (if applicable).

The backup is intended to be consumed by pkgacct.

This function returns a hash reference of the backup
data.

=over 2

=item Input

=over 3

=item $mysql_handle C<OBJECT>

    A Cpanel::Mysql or Cpanel::Mysql::Basic object

=item $cpconf C<HASHREF>

    cpanel configuration from
    Cpanel::Config::LoadCpConf::loadcpconf*

=item $domains_ar C<ARRAYREF>

    An arrayref of domains that the user
    controls.

=back

=back

=cut

sub fetch_backup_as_hr {
    my ( $mysql_handle, $cpconf, $domains_ar ) = @_;

    die "Need domains!" if !@$domains_ar;

    $cpconf ||= Cpanel::Config::LoadCpConf::loadcpconf_not_copy();

    my %backup = ( ALIVE => 'ALIVE' );

    # allow more time for dumpsql to run
    my $alarm = Cpanel::Alarm->new( $Cpanel::Config::Constants::MySQL::TIMEOUT_MYSQLDUMP, sub { die "Timeout while running fetch_backup_as_hr" } );

    my @SYSTEMDBS = ('mysql');

    if ( !( exists $cpconf->{'roundcube_db'} && $cpconf->{'roundcube_db'} eq 'sqlite' ) ) {
        push @SYSTEMDBS, 'roundcube';
    }

    my @dbs = $mysql_handle->listdbs();

    $backup{LISTDBS}         = \@dbs;
    $backup{LASTUPDATETIMES} = { map { $_ => $mysql_handle->last_update_time($_) } ( @SYSTEMDBS, @dbs ) };
    $backup{DUMPSQL}         = $mysql_handle->fetch_grants();
    $backup{SQLAUTH}         = $mysql_handle->get_authentication_plugin_type();

    if ( grep( /roundcube/, @SYSTEMDBS ) && $mysql_handle->{'hasmysqlso'} ) {
        my $user = $mysql_handle->{'cpuser'};

        # if we change this here, we must change it in pkgacct as well -- changed to use the same logic in to be merged case 40362
        my $sql_dnslist = join( ',', map { $mysql_handle->{'dbh'}->quote($_) } grep { index( $_, '*' ) == -1 } @$domains_ar );
## case 16846: adding "username = '$user'" to ensure the system users that use webmail are converted
        my $ids_ref;
        try {
            my $query = "SELECT user_id FROM roundcube.users WHERE BINARY username = ? OR BINARY SUBSTRING_INDEX(username,'\@',-1) IN (${sql_dnslist});";
            $ids_ref = $mysql_handle->{'dbh'}->selectall_arrayref( $query, undef, $user );
        }
        catch {
            local $@ = $_;
            warn;
        };

        $backup{ROUNDCUBEIDS} = ( ref $ids_ref && @$ids_ref ) ? join( ',', map { $_->[0] } @$ids_ref ) : '';
    }

    return \%backup;
}

1;
