package Cpanel::Resolvers::Check;

# cpanel - Cpanel/Resolvers/Check.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::TimeHiRes                ();
use Cpanel::Resolvers                ();
use Cpanel::Resolvers::Check::Status ();
use Cpanel::Parallelizer             ();
use Net::DNS::Resolver               ();

our $MAXIMUM_TIME_ALLOWED_TO_RESPOND_BEFORE_CONSIDERED_SLOW = 1;

our $MAXIMUM_RATIO_OF_REQUESTS_TO_FAIL_BEFORE_UNRELIABLE = 0.65;    #If 65% or more requests fail, we mark the resolver as unreliable
our $MAXIMUM_RATIO_OF_REQUESTS_TO_BE_SLOW                = 0.65;    #If 65% of more requests take longer than $MAXIMUM_TIME_ALLOWED_TO_RESPOND_BEFORE_CONSIDERED_SLOW, we mark the resolver as slow

#overridden in tests
our @DOMAINS_TO_ATTEMPT_TO_RESOLVE = (
    'captive.apple.com',
    'connectivitycheck.android.com',
    'google.com',
    'cpanel.com',
    'yahoo.com',
    'ebay.com',
    'amazon.com',
    'facebook.com',
    'live.com',
    'reddit.com',
);

#Returns a structure like:
#   {
#       state => Cpanel::Resolvers::Check::Status instance
#       resolver_state => {
#           $ip_addr_of_resolver => {
#               status => Cpanel::Resolvers::Check::Status instance
#               tests => {
#                   $domain_resolved => {
#                       addresses => \@list_of_resolved_ip_addresses
#                       duration: # of seconds
#                       responded: 0 or 1
#                   }
#               }
#           }
#       }
#   }
#
sub check_resolvers_performance {
    my %RESOLVER_STATE;
    _fill_resolvers_state( \%RESOLVER_STATE );
    _fill_resolvers_status_from_state( \%RESOLVER_STATE );

    return {
        'state'          => _get_overall_state_from_resolvers_state( \%RESOLVER_STATE ),
        'resolver_state' => \%RESOLVER_STATE
    };
}

sub _fill_resolvers_status_from_state {
    my ($resolver_state) = @_;

    my $number_of_domains_to_test           = scalar @DOMAINS_TO_ATTEMPT_TO_RESOLVE;
    my $number_of_failures_to_be_unreliable = ( scalar @DOMAINS_TO_ATTEMPT_TO_RESOLVE * $MAXIMUM_RATIO_OF_REQUESTS_TO_FAIL_BEFORE_UNRELIABLE );
    my $number_of_slow_requests_to_be_slow  = ( scalar @DOMAINS_TO_ATTEMPT_TO_RESOLVE * $MAXIMUM_RATIO_OF_REQUESTS_TO_BE_SLOW );

    foreach my $ip ( keys %{$resolver_state} ) {
        my $test_results                      = $resolver_state->{$ip}{'tests'};
        my $number_of_requests_not_responding = scalar grep { $test_results->{$_}{'responded'} == 0 } keys %{$test_results};
        my $number_of_slow_responses          = scalar grep { !$test_results->{$_}{'duration'} || $test_results->{$_}{'duration'} > $MAXIMUM_TIME_ALLOWED_TO_RESPOND_BEFORE_CONSIDERED_SLOW } keys %{$test_results};

        #It’s unsure for now whether there can be non-mutually-exclusive
        #error states, so currently this is implemented as a list.
        my @failures;

        if ( $number_of_requests_not_responding == $number_of_domains_to_test ) {
            push @failures, 'failed';
        }
        elsif ( $number_of_requests_not_responding >= $number_of_failures_to_be_unreliable ) {    # Someone else could be down right?
            push @failures, 'unreliable';
        }
        elsif ( $number_of_slow_responses >= $number_of_slow_requests_to_be_slow ) {              # Someone else could be down right?
            push @failures, 'slow';
        }

        $resolver_state->{$ip}{'status'} = Cpanel::Resolvers::Check::Status->new(@failures);
    }
    return 1;
}

#tested directly in tests
sub _fill_resolvers_state {
    my ($resolver_state) = @_;

    my $current_resolvers = Cpanel::Resolvers::fetchresolvers();

    #push @{$current_resolvers}, '4.2.2.2', '8.8.8.8', '3.2.22.2';
    my $parallelizer = Cpanel::Parallelizer->new();
    foreach my $ip ( @{$current_resolvers} ) {
        $resolver_state->{$ip}{'tests'} = {};
        $parallelizer->queue(
            \&_check_resolver_by_ip,
            [$ip],
            sub {
                my ( $ip, $tests ) = @_;
                $resolver_state->{$ip}{'tests'} = $tests;
                return 1;
            },
        );
    }

    $parallelizer->run();
    return;
}

sub _check_resolver_by_ip {
    my ($ip) = @_;

    my $tests    = {};
    my $resolver = Net::DNS::Resolver->new( nameservers => [$ip], tcp_timeout => 2, udp_timeout => 2, retry => 0 );
    foreach my $test_domain (@DOMAINS_TO_ATTEMPT_TO_RESOLVE) {
        $tests->{$test_domain}{'responded'} = 0;
        my $time_before = Cpanel::TimeHiRes::time();
        my $reply       = $resolver->query( $test_domain, 'A' );
        my $time_after  = Cpanel::TimeHiRes::time();

        #The sprintf() helps to prevent floating-point weirdness.
        $tests->{$test_domain}{'duration'} = sprintf( "%0.10f", ( $time_after - $time_before ) );

        next if !$reply;
        my @answer = $reply->answer();
        next if !@answer;
        my @records;
        $tests->{$test_domain}{'responded'} = 1;

        foreach my $rr (@answer) {
            if ( $rr->isa('Net::DNS::RR::A') ) {
                push @records, $rr->address();
            }
        }
        $tests->{$test_domain}{'addresses'} = \@records;

    }
    return ( $ip, $tests );
}

#tested directly
sub _get_overall_state_from_resolvers_state {
    my ($resolver_state) = @_;

    my $resolver_count = keys %$resolver_state;

    if ( !$resolver_count ) {
        return Cpanel::Resolvers::Check::Status->new('missing');    # no resolvers - Send notification
    }

    my $performant_count = 0;
    my $slow_count       = 0;
    my $unreliable_count = 0;
    my $failed_count     = 0;

    for my $res ( values %$resolver_state ) {
        my $st = $res->{'status'};

        if ( $st->is_ok() ) {
            $performant_count++ if $st->is_ok();
        }
        else {
            $slow_count++       if $st->error_is('slow');
            $unreliable_count++ if $st->error_is('unreliable');
            $failed_count++     if $st->error_is('failed');
        }
    }

    if ( $performant_count == $resolver_count ) {
        return Cpanel::Resolvers::Check::Status->new();    # All happy
    }

    if ( $failed_count == $resolver_count ) {
        return Cpanel::Resolvers::Check::Status->new('failed');    # Everything is broken - Send notification
    }

    if ( $unreliable_count || $failed_count ) {
        return Cpanel::Resolvers::Check::Status->new('unreliable');    # At least one server is failing some requests - Send notification
    }

    if ($slow_count) {
        return Cpanel::Resolvers::Check::Status->new('slow');          # At least one nameserver is slow to respond - Send notification
    }

    # If this happens we have a bug
    die "BUG: Could not determine resolver state";
}

1;
