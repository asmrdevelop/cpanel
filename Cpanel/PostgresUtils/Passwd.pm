package Cpanel::PostgresUtils::Passwd;

# cpanel - Cpanel/PostgresUtils/Passwd.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)
#
use Cpanel::SafeRun::Object       ();
use Cpanel::Logger                ();
use Cpanel::DbUtils               ();
use Cpanel::AdvConfig             ();
use Cpanel::PostgresUtils         ();
use Cpanel::PostgresUtils::PgPass ();
use Cpanel::PostgresUtils::Quote  ();
use Cpanel::PwCache               ();
use Cpanel::AccessIds::SetUids    ();

our $VERSION = 1.1;

# This will only work if run by root due to the calls to Cpanel::AdvConfig.
sub passwd {
    my $password = shift;
    my $file     = shift;
    my $user     = Cpanel::PostgresUtils::PgPass::getpostgresuser();
    my ( $uid, $gid ) = ( Cpanel::PwCache::getpwnam($user) )[ 2, 3 ];
    my $trusted_status = Cpanel::AdvConfig::generate_config_file( { 'service' => 'postgres', 'allow_no_password' => 1 } );
    if ( !defined $uid || !defined $gid ) {
        return wantarray ? ( 0, qq[Cannot find user/group for user '$user'] ) : 0;
    }

    if ( !$trusted_status ) {
        return wantarray ? ( 0, 'Password change failed' ) : 0;
    }

    my $pgsql_data = Cpanel::PostgresUtils::find_pgsql_data();
    if ( !defined $pgsql_data ) {
        return wantarray ? ( 0, q[Cannot find psql_data directory] ) : 0;
    }
    my $pg_hba = $pgsql_data . '/pg_hba.conf';

    if ( -e $pg_hba ) {

        # If we change the uid/gid on the file we need to update Whostmgr::Postgres::update_config
        chown( $uid, $gid, $pg_hba ) or warn "Failed to chown($uid,$gid,$pg_hba): $!";

        # If we change the mode on the file we need to update Whostmgr::Postgres::update_config
        chmod( 0600, $pg_hba ) or warn "Failed to chmod(0600,$pg_hba): $!";

        Cpanel::PostgresUtils::reload();
    }

    unless ( _update_db_passwd($password) ) {
        return wantarray ? ( 0, 'Unable to update database password' ) : 0;
    }
    my $untrusted_status = Cpanel::AdvConfig::generate_config_file( { 'service' => 'postgres', 'allow_no_password' => 0 } );
    if ( !$untrusted_status ) {
        return wantarray ? ( 0, 'Unable to update pg_hba.conf' ) : 0;
    }

    if ( -e $pg_hba ) {

        # If we change the uid/gid on the file we need to update Whostmgr::Postgres::update_config
        chown( $uid, $gid, $pg_hba ) or warn "Failed to chown($uid,$gid,$pg_hba): $!";

        # If we change the mode on the file we need to update Whostmgr::Postgres::update_config
        chmod( 0600, $pg_hba ) or warn "Failed to chmod(0600,$pg_hba): $!";
        Cpanel::PostgresUtils::reload();

    }

    my @pgpass_file;
    my $haspgpass = 0;

    my $pg_version = Cpanel::PostgresUtils::get_version();

    # Handling of escaped colons in pgpass was applied in libpq 9.2
    if ( $pg_version >= 9.2 ) {
        $password = _escape_passwd_for_pgpass($password);
    }

    if ( open my $pgpass_fh, '<', $file ) {

        while ( my $line = readline $pgpass_fh ) {
            chomp $line;

            # split 5 is needed because the password
            # may contain a colon
            my @items = split( /:/, $line, 5 );
            if ( $items[3] eq $user ) {
                push @pgpass_file, '*:*:*:' . $user . ':' . $password;
                $haspgpass = 1;
            }
            else {
                push @pgpass_file, $line;
            }
        }
        close $pgpass_fh;
    }
    if ( !$haspgpass ) {
        unshift @pgpass_file, '*:*:*:' . $user . ':' . $password;
    }

    if ( open my $pgpass_fh, '>', $file ) {
        chmod 0600, $file;
        print {$pgpass_fh} join( "\n", @pgpass_file ) . "\n";
        close $pgpass_fh;
    }
    else {
        return wantarray ? ( 0, 'Unable to write .pgpass file' ) : 0;
    }

    return wantarray ? ( 1, 'Password successfully changed' ) : 1;
}

sub _update_db_passwd {
    my $sqlpasswd = Cpanel::PostgresUtils::Quote::quote(shift);
    my $psql      = Cpanel::DbUtils::find_psql();
    my $user      = Cpanel::PostgresUtils::PgPass::getpostgresuser();

    return unless $psql && -x $psql;

    local $SIG{'PIPE'} = 'IGNORE';

    my $logger = Cpanel::Logger->new();

    my $saferun = Cpanel::SafeRun::Object->new(
        'stdin'       => "ALTER USER $user WITH PASSWORD $sqlpasswd;\n\\q\n",                                                           # quotes for $sqlpasswd are embedded in the variable by the quote subroutine.
        'program'     => $psql,
        'args'        => [ '-U', $user, 'template1' ],                                                                                  # # Must be template1 for resets
        'before_exec' => sub { chdir("/") or die "Failed to change directory to /: $!"; Cpanel::AccessIds::SetUids::setuids($user) },
    );

    if ( $saferun->CHILD_ERROR() ) {

        # Do not use ->warn here to avoid the password ending up in the log
        $logger->info( "Failed to _update_db_passwd for $user: " . join( ', ', $saferun->stderr(), $saferun->stdout() ) );
    }

    return 1;
}

sub _escape_passwd_for_pgpass {
    my $passwd = shift;
    $passwd =~ s{\\}{\\\\}g;
    $passwd =~ s{:}{\\:}g;
    return $passwd;
}
