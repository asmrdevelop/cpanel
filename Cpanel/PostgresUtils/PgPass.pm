package Cpanel::PostgresUtils::PgPass;

# cpanel - Cpanel/PostgresUtils/PgPass.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::LoadModule    ();
use Cpanel::PwCache       ();
use Cpanel::PostgresUtils ();

my $root_pgpass_file;

sub find_pgpass {

    # ** This cannot be set outside a sub {} or it will end up compiled in
    if ( !defined $root_pgpass_file ) {
        my ($root_homedir) = ( Cpanel::PwCache::getpwnam('root') )[7];
        $root_pgpass_file = $root_homedir . '/.pgpass';
    }

    if ( -e $root_pgpass_file ) {
        return $root_pgpass_file;
    }
    else {
        return;
    }
}

sub pgpass {
    my $pgpass = find_pgpass();

    my $pg_version = Cpanel::PostgresUtils::get_version();

    my %stash;
    my $lineno = 0;
    if ( $pgpass && open( my $fh, '<', $pgpass ) ) {
        while ( my $line = <$fh> ) {
            chomp($line);
            my @line = split /:/, $line, 5;

            # Handling of escaped colons in pgpass was applied in libpq 9.2
            if ( $pg_version >= 9.2 ) {

                # Unescape password
                $line[4] =~ s/\\(.)/$1/g;
            }

            $stash{ $line[3] } = {
                hostname => $line[0],
                port     => $line[1],
                database => $line[2],
                password => $line[4],    # May contain ':'
                lineno   => ++$lineno,
            };
        }
        close($fh);
    }
    return wantarray ? %stash : \%stash;
}

sub get_server {
    my $pgpass = pgpass();
    my $pguser = getpostgresuser();

    my $server = ( $pguser && $pgpass->{$pguser} ) ? $pgpass->{$pguser}{'hostname'} : undef;

    if ( !$server || $server eq '*' ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::DIp::MainIP');
        return Cpanel::DIp::MainIP::getmainserverip();
    }
    else {
        Cpanel::LoadModule::load_perl_module('Cpanel::SocketIP');
        return Cpanel::SocketIP::_resolveIpAddress($server);
    }
}

sub getpostgresuser {
    return 'postgres' if Cpanel::PwCache::getpwnam('postgres');
    return 'pgsql'    if Cpanel::PwCache::getpwnam('pgsql');
    return;
}

1;
