package Whostmgr::Transfers::Session::Setup;

# cpanel - Whostmgr/Transfers/Session/Setup.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)

use Try::Tiny;

use Cpanel::LoadModule                   ();
use Whostmgr::Transfers::Session::Config ();

#
# See Whostmgr::Transfers::Session::Processor::_MAX_ALLOWED_RSS_KIB
#

our $AVG_MEMORY_USAGE_BY_THREAD_TYPE_MEGS = {
    'transfer' => {
        '64' => 80,
        '32' => 50
    },
    'restore' => {
        '64' => 170,
        '32' => 130,
    }
};

our $FREE_PERCENTAGE = {
    'hard' => 0.05,
    'soft' => 0.20,
};

our $MINIMUM_MULTIPLIER = {
    'hard' => 0.66,
    'soft' => 1.50,
};

our $MAX_RECOMMENDED_THREADS_HARD_LIMIT = 5;

#This receives two arguments:
#   - a hashref of options to pass to Whostmgr::Transfers::Session's constructor
#   - a hashref that will be passed to that instance's set_data() method
#
sub setup_session_obj {
    my ( $new_opts, $set_data ) = @_;
    my ( $err_obj, $session_obj );

    my $module = 'Whostmgr::Transfers::Session';
    if ( $new_opts->{'type'} && $new_opts->{'type'} eq 'SessionDB' ) {
        $module = 'Whostmgr::Transfers::SessionDB';
    }

    try {
        Cpanel::LoadModule::load_perl_module($module);

        $session_obj = $module->new( %{$new_opts} );

        if ($set_data) {
            $session_obj->set_data($set_data);
        }
    }
    catch {
        $err_obj = $_;
    };

    if ($err_obj) {
        if ( ref $err_obj && $err_obj->isa('Cpanel::Exception') ) {
            return ( 0, $err_obj->to_locale_string() );
        }
        else {
            return ( 0, $err_obj );
        }
    }

    return ( 0, 'Unknown Error' ) if !$session_obj;

    return ( 1, $session_obj );

}

sub get_transfer_restore_thread_recommendations {
    my ( $available_memory, $cpus ) = @_;

    my $bits = 64;

    my $MAX_RECOMMENDED_THREADS_SOFT_LIMIT = ( $cpus < $MAX_RECOMMENDED_THREADS_HARD_LIMIT ? $cpus : $MAX_RECOMMENDED_THREADS_HARD_LIMIT ) || 1;
    my %limits;

    # TODO: use remote cpu count and memory to calculate transfer threads
    # and retain using local cpu count and memory to calculate restore threads

    for my $type (qw/hard soft/) {
        my $free = int( $available_memory * $FREE_PERCENTAGE->{$type} );

        my $min_free = ( $AVG_MEMORY_USAGE_BY_THREAD_TYPE_MEGS->{'restore'}{$bits} * $MINIMUM_MULTIPLIER->{$type} );

        my $available = $available_memory - ( $free < $min_free ? $min_free : $free );

        for my $thread_type (qw/transfer restore/) {
            $limits{"${thread_type}_threads_${type}_limit"} = int( $available / $Whostmgr::Transfers::Session::Config::NUMPHASES / $AVG_MEMORY_USAGE_BY_THREAD_TYPE_MEGS->{$thread_type}{$bits} );
        }
    }

    foreach my $limit ( keys %limits ) {
        my $max = ( $limit =~ m{_hard_} ? $MAX_RECOMMENDED_THREADS_HARD_LIMIT : $MAX_RECOMMENDED_THREADS_SOFT_LIMIT );

        if ( $limits{$limit} > $max ) {
            $limits{$limit} = $max;
        }
        elsif ( $limits{$limit} < 1 ) {
            $limits{$limit} = 1;
        }
    }

    $limits{'thread_recommendations_are_max'} = ( $limits{'restore_threads_soft_limit'} >= $MAX_RECOMMENDED_THREADS_HARD_LIMIT && $limits{'transfer_threads_soft_limit'} >= $MAX_RECOMMENDED_THREADS_HARD_LIMIT ) ? 1 : 0;

    return \%limits;
}

1;
