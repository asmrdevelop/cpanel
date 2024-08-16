package Whostmgr::Accounts::Remove::Cleanup::RoundCubeMySQL;

# cpanel - Whostmgr/Accounts/Remove/Cleanup/RoundCubeMySQL.pm
#                                                  Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Slurper                  ();
use Cpanel::ConfigFiles              ();
use Cpanel::MysqlUtils::MyCnf::Basic ();
use Whostmgr::Email                  ();

=encoding utf-8

=head1 NAME

Whostmgr::Accounts::Remove::Cleanup::RoundCubeMySQL

=head1 SYNOPSIS

    Whostmgr::Accounts::Remove::Cleanup::RoundCubeMySQL::clean_up( $obj )

=head1 DESCRIPTION

Account removal’s RoundCube MySQL cleanup, because we probably should have
been doing this for a long time anyways.

=head1 FUNCTIONS

=head2 clean_up( $obj )

Removes data sitting around in the `users` table of the `roundcube` database
corresponding to the user being deleted and their webmail users.
ON DELETE CASCADE triggers take care of the rest.

Accepts HASHREF of data from L<Cpanel::Config::LoadCpUserData>.

Returns undef, as the caller never checks the return value anyways.

=cut

sub skip_this {
    my $slurpee = Cpanel::Slurper::read($Cpanel::ConfigFiles::cpanel_config_file);
    my ($rc_db) = $slurpee =~ /^roundcube_db=([a-z]+)$/m;
    $rc_db ||= 'sqlite';
    return $rc_db ne 'mysql';
}

sub clean_up ( $cleanup_obj = {} ) {

    # Don't *use* this because it isn't safe to link libssl.so in compiled
    # contexts.
    require Cpanel::Email::RoundCube::DBI;
    my $cpuser_hr = $cleanup_obj->{'_cpuser_data'};
    my $username  = $cleanup_obj->{'_username'} || $cpuser_hr->{'USER'};

    my @pops = ( $username, @{ Whostmgr::Email::list_pops_for($username) } );

    my $mysql_user = Cpanel::MysqlUtils::MyCnf::Basic::getmydbuser('root') || 'root';
    my $mysql_host = Cpanel::MysqlUtils::MyCnf::Basic::getmydbhost('root') || 'localhost';
    my $mysql_port = Cpanel::MysqlUtils::MyCnf::Basic::getmydbport('root') || 3306;

    my $dbh = Cpanel::Email::RoundCube::DBI::mysql_db_connect(
        'roundcube',
        $mysql_host,
        $mysql_user,
        Cpanel::MysqlUtils::MyCnf::Basic::getmydbpass('root'),
        undef,
        $mysql_port,
    );

    my $qs            = "?" . ", ?" x $#pops;
    my $query         = "DELETE FROM `users` WHERE `username` IN ( $qs );";
    my $sth           = $dbh->prepare($query);
    my $affected_rows = $sth->execute(@pops);
    $affected_rows = 0 if $affected_rows == '0E0';
    if ( $affected_rows != scalar(@pops) ) {
        $sth = $dbh->prepare("SELECT `username` FROM `users` WHERE `username` IN ( $qs );");
        $sth->execute(@pops);
        my $remaining     = $dbh->selectall_arrayref($sth);
        my $remaining_bit = '';
        $remaining_bit = 'Remaining users: ' . join( " ", @$remaining ) if @$remaining;
        die "Dropped $affected_rows from roundcube.users, but was expecting to drop " . scalar(@pops) . ". Manual cleanup may be required? $remaining_bit";
    }
    return;
}

1;
