package Whostmgr::Postgres;

# cpanel - Whostmgr/Postgres.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::AdvConfig                ();
use Cpanel::Config::Users            ();
use Cpanel::Logger                   ();
use Cpanel::PasswdStrength::Generate ();
use Cpanel::PostgresUtils            ();
use Cpanel::PostgresUtils::Passwd    ();
use Cpanel::PostgresUtils::PgPass    ();
use Cpanel::SafeRun::Simple          ();
use Cpanel::SafeRun::Errors          ();
use Cpanel::PwCache                  ();

*get_version = *Cpanel::PostgresUtils::get_version;

my %cache;

sub update_config {
    my $allow_no_password = shift;

    if ( !exists $cache{'pguser'} ) {
        $cache{'pguser'} = Cpanel::PostgresUtils::PgPass::getpostgresuser();
    }
    if ( !$cache{'pguser'} ) {
        $cache{'pguser'} = undef;
        my $message = 'Failed to locate postgresql user';

        Cpanel::Logger::logger(
            {
                'message'   => $message,
                'level'     => 'warn',
                'service'   => 'whostmgr2',
                'output'    => 0,
                'backtrace' => 0,
            }
        );
        return wantarray ? ( 0, $message ) : 0;
    }
    else {
        if ( !exists $cache{'pgsql_data'} ) {
            $cache{'pgsql_data'} = Cpanel::PostgresUtils::find_pgsql_data();
        }

        if ( $cache{'pgsql_data'} ) {
            if ( !-e $cache{'pgsql_data'} ) {
                mkdir $cache{'pgsql_data'};
            }
            $cache{'pg_hba'} = $cache{'pgsql_data'} . '/pg_hba.conf';

        }
        else {
            $cache{'pgsql_data'} = undef;
            my $message = 'Failed to determine postgresql data directory';

            Cpanel::Logger::logger(
                {
                    'message'   => $message,
                    'level'     => 'warn',
                    'service'   => 'whostmgr2',
                    'output'    => 0,
                    'backtrace' => 0,
                }
            );
            return wantarray ? ( 0, $message ) : 0;
        }
    }

    if ( !exists $cache{'major_version'} ) {
        ( $cache{'major_version'}, $cache{'minor_version'} ) = get_version();
    }

    if ( !$cache{'major_version'} ) {
        $cache{'major_version'} = undef;
        my $message = $cache{'minor_version'} ? $cache{'minor_version'} : 'Unable to determine psql version';
        delete $cache{'minor_version'};
        return wantarray ? ( 0, $message ) : 0;
    }

    my $supported_version = 0;
    if ( $cache{'major_version'} > 7 || ( $cache{'major_version'} == 7 && $cache{'minor_version'} >= 4 ) ) {
        $supported_version = 1;
    }

    if ($supported_version) {
        my $pgpasswd       = Cpanel::PasswdStrength::Generate::generate_password(8);
        my $pg_pass_status = passwd($pgpasswd);

        my $status = Cpanel::AdvConfig::generate_config_file( { 'service' => 'postgres', 'allow_no_password' => $allow_no_password } );

        if ( $status && $pg_pass_status ) {
            my ( $uid, $gid ) = ( Cpanel::PwCache::getpwnam( $cache{'pguser'} ) )[ 2, 3 ];

            # If we change the uid/gid on the file we need to update Cpanel::PostgresUtils::Passwd::passwd
            chown( $uid, $gid, $cache{'pg_hba'} ) or warn "Failed to chown($uid,$gid,$cache{'pg_hba'}): $!";

            # If we change the mode on the file we need to update Cpanel::PostgresUtils::Passwd::passwd
            chmod( 0600, $cache{'pg_hba'} ) or warn "Failed to chmod(0600,$cache{'pg_hba'}): $!";

            Cpanel::PostgresUtils::ensure_secure_socket();

            Cpanel::SafeRun::Simple::saferun('/usr/local/cpanel/bin/build_global_cache');    # the restart done in cpsessetup requires the global cache state to be up to date
            Cpanel::SafeRun::Simple::saferun('/usr/local/cpanel/bin/cpsessetup');            # do postgres specific items

            return wantarray ? ( 1, 'Configuration successfully updated' ) : 1;
        }
        else {
            return wantarray ? ( 0, "Failed to update $cache{'pg_hba'}: $!" ) : 0;
        }
    }
    else {
        return wantarray ? ( 0, "Unsupported version of PostgreSQL." ) : 0;
    }
}

sub reload {
    return Cpanel::PostgresUtils::reload( @cache{qw/pguser pgsql_data pg_ctl/} );
}

sub passwd {
    my $password = shift;

    my ($root_homedir) = ( Cpanel::PwCache::getpwnam('root') )[7];
    my $root_pgpass_file = $root_homedir . '/.pgpass';

    my @ret = Cpanel::PostgresUtils::Passwd::passwd( $password, $root_pgpass_file );

    # Now, let's bust the connection status cache, as resetting the password
    # could very well fix (or make) a busted connection. Thus we *should*
    # force a re-check after resetting the password.
    require Cpanel::PostgresAdmin::Check;
    require Cpanel::CachedCommand::Utils;
    my $datastore_file = Cpanel::CachedCommand::Utils::get_datastore_filename($Cpanel::PostgresAdmin::Check::POSTGRES_RUN_KEY);
    require Cpanel::Autodie::Unlink;
    Cpanel::Autodie::Unlink::unlink_if_exists($datastore_file);

    return @ret;
}

sub create_dbowners_for_cpusers {
    my @cpusers = Cpanel::Config::Users::getcpusers();

    foreach my $cpuser (@cpusers) {
        my $pgpasswd = Cpanel::PasswdStrength::Generate::generate_password(8);
        local $ENV{'REMOTE_PASSWORD'} = $pgpasswd;
        local $ENV{'CPRESELLER'}      = '';

        my $uid = ( Cpanel::PwCache::getpwnam($cpuser) )[2];
        Cpanel::SafeRun::Errors::saferunnoerror( '/usr/local/cpanel/bin/postgresadmin', $uid, 'UPDATEDBOWNER' );
    }

    return ( 1, "PostgreSQL users created" );
}

1;
