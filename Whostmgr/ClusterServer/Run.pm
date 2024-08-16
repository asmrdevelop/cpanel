#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - Whostmgr/ClusterServer/Run.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::ClusterServer::Run;

use strict;

use Cpanel::Cpu             ();
use Cpanel::Locale          ();
use Cpanel::Parallelizer    ();
use Whostmgr::ClusterServer ();

my $locale;

our $MAX_PROCESSES = 4;    # never go over that limit

sub update_config {
    my ($conf) = @_;

    return unless $conf && ref $conf eq 'HASH' && keys %$conf;

    # append to current configuration
    return _run_query( 'update_updateconf', { 'api.version' => 1, %$conf } );
}

sub version {
    return _run_query('version');
}

# helper to run a query on all remote servers
sub _run_query {
    my ( $query, $args ) = @_;

    $locale ||= Cpanel::Locale->get_handle();

    my $servers;
    {
        my $linked_servers = Whostmgr::ClusterServer->new();
        $servers = $linked_servers->get_list();
        return unless $servers && ref $servers eq 'HASH' && scalar %$servers;
    }

    my @results;
    my $cpucount = Cpanel::Cpu::getcpucount() || 1;
    $cpucount = $MAX_PROCESSES if $MAX_PROCESSES && $cpucount > $MAX_PROCESSES;
    my $parallelizer = Cpanel::Parallelizer->new( process_limit => $cpucount, process_time_limit => 60 );

    my $run = sub {
        my ( $host, $user, $key ) = @_;

        # only load Whostmgr::API::Query in subprocess, no need to load it in the main binaries
        eval q{require Whostmgr::API::Query; 1} or die "Cannot load Whostmgr::API::Query: $@";    # hide from perlcc
        my $code = 'Whostmgr::API::Query'->can('new');

        # use JSON api as Cpanel::JSON is compiled in nearly all binaries
        my $api = $code->( 'Whostmgr::API::Query', hostname => $host, user => $user, hash => $key, api => 'json-api' );
        my $result;

        eval { $result = $api->query( $query, $args ) };

        if ( $@ || !$result || defined $result->{'error'} ) {
            my $debug = '';
            $debug .= "Query died with: " . $@ . "\n"           if $@;
            $debug .= "Error from query: " . $result->{'error'} if $result && $result->{'error'};

            if ( !$result ) {
                return [ 'ERROR', $locale->maketext( "Cannot connect to host: [_1]", $host ), $debug ];
            }
            else {
                return [ 'ERROR', $locale->maketext( "Update failed on host “[_1]”: [_2]", $host, $result->{'error'} ), $debug ];
            }
        }
        return ['OK'];
    };

    foreach my $host ( sort keys %$servers ) {
        my $server = $servers->{$host};    # alias
        $parallelizer->queue(
            $run,
            [ $host, $server->{user}, $server->{key} ],
            sub {                          # success from subprocess
                my $return = shift;
                return unless ref $return eq 'ARRAY';
                my ( $status, $msg, $debug ) = @$return;
                my %server_results = (
                    server => $host,
                    status => $status,
                    $debug ? ( debug => $debug ) : ()
                );

                if ( $status ne 'OK' || ( $msg && $msg ne '' ) ) {
                    $server_results{'message'} = $msg;
                }

                push @results, \%server_results;

                return;
            },
            sub {    # subprocess fails
                push @results,
                  {
                    server  => $host,
                    status  => 'ERROR',
                    message => $locale->maketext( "Cannot connect to host: [_1]", $host ),
                    debug   => 'cPanel::Parallelizer issue'
                  };
                return;
            }
        );
    }

    $parallelizer->run();

    # my $ok = scalar @errors ? 0 : 1;
    return ( \@results );
}

1;
