package Cpanel::ServiceManager::Services::Postgresql;

# cpanel - Cpanel/ServiceManager/Services/Postgresql.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Moo;

use cPstrict;    # restore hints

use Cpanel::ServiceManager::Base ();
use Cpanel::PostgresUtils        ();
use Cpanel::PwCache              ();
use Cpanel::OS                   ();

extends 'Cpanel::ServiceManager::Base';

has '_pgctl'             => ( is => 'ro', lazy => 1, builder => 1 );
has '_pgsqldir'          => ( is => 'ro', lazy => 1, default => sub { Cpanel::PostgresUtils::find_pgsql_data() } );
has '_postgres_is_setup' => ( is => 'ro', lazy => 1, default => sub { my $p = $_[0]->_pgctl; return $p && -x $p && $_[0]->_pgsqldir ? 1 : 0 } );

has '+processowner'   => ( is => 'rw', lazy => 1, default => sub { 'postgres' } );
has '+service_binary' => ( is => 'rw', lazy => 1, default => sub { return $_[0]->_postgres_is_setup ? $_[0]->_pgctl : $_[0]->SUPER::service_binary() } );
has '+startup_args'   => ( is => 'rw', lazy => 1, default => sub { return $_[0]->_postgres_is_setup ? [ '-D', $_[0]->_pgsqldir, 'start' ] : undef } );
has '+shutdown_args'  => ( is => 'rw', lazy => 1, default => sub { return $_[0]->_postgres_is_setup ? [ '-D', $_[0]->_pgsqldir, 'stop' ] : undef } );
has '+pidfile'        => ( is => 'rw', lazy => 1, default => sub { return $_[0]->_postgres_is_setup ? $_[0]->_pgsqldir . '/postmaster.pid' : undef } );
has '+is_enabled'     => ( is => 'rw', lazy => 1, default => sub { return $_[0]->_postgres_is_setup ? $_[0]->SUPER::is_enabled() : 0 } );

has '+restart_attempts' => ( is => 'ro', default => 2 );

has '+doomed_rules' => (
    is      => 'ro',
    lazy    => 1,
    default => sub {
        return [ Cpanel::OS::is_systemd() ? 'postgres' : 'postmaster' ];
    }
);

# Lifted from
sub _build__pgctl {
    foreach my $loc ( '/usr/bin/pg_ctl', '/usr/local/bin/pg_ctl', '/opt/local/lib/postgresql82/bin/pg_ctl' ) {
        return $loc if -x $loc;
    }

    return;
}

sub check ( $self, @args ) {

    # should happen before SUPER::check
    $self->_repair_attempt();

    return $self->SUPER::check(@args);
}

sub restart_attempt ( $self, $attempt = 1 ) {

    $self->_repair_attempt() if $attempt == 1;

    return 1;
}

sub _repair_attempt ($self) {

    return unless $self->is_enabled();

    require Cpanel::PostgresUtils;

    my $pgsql_home = Cpanel::PostgresUtils::find_pgsql_home();

    return unless $pgsql_home && -d "$pgsql_home/data";

    if (   !-e "$pgsql_home/data/PG_VERSION"
        && !-e "$pgsql_home/data/base"
        && !-e "$pgsql_home/data/global"
        && -e "/usr/bin/initdb" ) {
        print "The Postgres database is not initialized. The system will now initialize it.\n";

        my $pg_hba_conf = "$pgsql_home/data/pg_hba.conf";

        my @PGA;

        if ( open( my $pga, '<', $pg_hba_conf ) ) {
            @PGA = <$pga>;
            close($pga);
        }

        unlink($pg_hba_conf);
        unlink("$pgsql_home/data/pg_hbc.conf");

        my $pg_user = getpwnam('postgres') ? 'postgres' : 'pgsql';
        system( 'su', '-l', $pg_user, '-c', '/usr/bin/initdb' );
        my ( $uid, $gid ) = ( Cpanel::PwCache::getpwnam($pg_user) )[ 2, 3 ];
        if ( open( my $pg_hba_fh, '>', "$pgsql_home/data/pg_hba.conf" ) ) {
            chown( $uid, $gid, $pg_hba_fh ) or warn "Failed to chown($uid,$gid,$pgsql_home/data/pg_hba.conf): $!";
            chmod( 0600, $pg_hba_fh )       or warn "Failed to chmod(0600,$pgsql_home/data/pg_hba.conf): $!";
            foreach (@PGA) { print {$pg_hba_fh} $_; }
            close($pg_hba_fh);
        }
        else {
            warn "Failed to open $pgsql_home/data/pg_hba.conf: $!";
        }
        print "Done\n";
    }

    return;
}

1;
