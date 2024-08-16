package Cpanel::Bandwidth::Remote;

# cpanel - Cpanel/Bandwidth/Remote.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Bandwidth::Remote

=head1 SYNOPSIS

    my $user_total = Cpanel::Bandwidth::Remote::fetch_remote_user_bandwidth(
        'santaclaus', 12, 2020,
    );

    my $user_total_hr = Cpanel::Bandwidth::Remote::fetch_all_remote_users_bandwidth(
        12, 2020,
    );

=head1 DESCRIPTION

This module contains logic to query remote nodes about their bandwidth usage.

=cut

#----------------------------------------------------------------------

use Cpanel::Exception               ();
use Cpanel::LinkedNode::Worker::WHM ();
use Cpanel::Try                     ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $sum = fetch_remote_user_bandwidth( $USERNAME, $MONTHNUM, $YEAR )

Fetches $USERNAME’s total remote bandwidth usage in bytes for all protocols
for the given $MONTHNUM (1 .. 12) and 4-digit $YEAR.

=cut

sub fetch_remote_user_bandwidth ( $username, $month, $year ) {
    my @promises;

    my $forker;

    Cpanel::LinkedNode::Worker::WHM::do_on_all_user_nodes(
        username      => $username,
        remote_action => sub ($node_obj) {
            _lazy_load_forker( \$forker );

            my $hostname = $node_obj->hostname();

            push @promises, $forker->do_in_child(
                sub {
                    return _fetch_remote_user_bw_in_child( $node_obj, $username, $month, $year );
                }
            )->catch(
                sub ($why) {
                    warn "Failed to fetch $username’s bandwidth usage from $hostname: $why";
                    return 0;
                }
            );
        },
    );

    my $sum = 0;

    _await(
        sub (@usages) {
            $sum += $_->[0] for @usages;
        },
        @promises,
    );

    return $sum;
}

=head2 $user_sum_hr = fetch_all_remote_users_bandwidth( $MONTHNUM, $YEAR )

Like C<fetch_remote_user_bandwidth()> but fetches usage for all local
cpusers who use >=1 child/worker nodes.

Returns a hashref of ( username => sum ).

=cut

sub fetch_all_remote_users_bandwidth ( $month, $year ) {
    my %node_promise;

    my $forker;

    my @cpusers = _get_all_cpusers();

    my %user_sum;

    # This iterates through all the cpusers but only sends as many
    # remote API requests as there are hostnames among the cpusers.
    # So if 1,000 cpusers use 3 remotes, there will be only 3 remote
    # API calls.
    for my $username (@cpusers) {
        Cpanel::LinkedNode::Worker::WHM::do_on_all_user_nodes(
            username      => $username,
            remote_action => sub ($node_obj) {
                $user_sum{$username} = 0;

                my $hostname = $node_obj->hostname();

                $node_promise{$hostname} ||= do {
                    _lazy_load_forker( \$forker );

                    $forker->do_in_child(
                        sub {
                            return _fetch_all_remote_node_bw_in_child( $node_obj, $month, $year );
                        }
                    )->catch(
                        sub ($why) {
                            warn "Failed to fetch bandwidth usage from $hostname: $why";
                            return {};
                        }
                    );
                };
            },
        );
    }

    _await(
        sub (@usages) {
            for my $resp_ar (@usages) {
                my $resp_hr = $resp_ar->[0];

                for my $username ( keys %user_sum ) {
                    $user_sum{$username} += $resp_hr->{$username} // 0;
                }
            }
        },
        values %node_promise,
    );

    return \%user_sum;
}

sub fetch_all_remote_users_domains_bandwidth ( $month, $year ) {
    my %node_promise;

    my $forker;

    my @cpusers = _get_all_cpusers();

    my %user_totals;

    # It’s possible for the controller & worker to have accounts that share
    # a username but that are *not* pieces of the same account. Thus, we
    # need to track the specific account/host relationships and restrict our
    # final result to those.
    my %hostname_usernames_lookup;

    for my $username (@cpusers) {
        Cpanel::LinkedNode::Worker::WHM::do_on_all_user_nodes(
            username      => $username,
            remote_action => sub ($node_obj) {
                my $hostname = $node_obj->hostname();

                $hostname_usernames_lookup{$hostname}{$username} = undef;

                return $node_promise{$hostname} ||= do {
                    _lazy_load_forker( \$forker );

                    $forker->do_in_child(
                        sub {
                            return [ $hostname, _fetch_all_remote_node_bw_with_domains_in_child( $node_obj, $month, $year ) ];
                        }
                    )->catch(
                        sub ($why) {
                            my $simple_why = Cpanel::Exception::get_string($why);
                            warn "Failed to fetch bandwidth usage from $hostname: $simple_why";
                            return [ $hostname, {} ];
                        }
                    );
                };
            },
        );
    }

    _await(
        sub (@usages) {
            for my $resp_ar (@usages) {
                my ( $hostname, $bw_hr ) = @{ $resp_ar->[0] };

                for my $username ( keys %$bw_hr ) {
                    next if !exists $hostname_usernames_lookup{$hostname}{$username};

                    my $user_total_hr = $user_totals{$username} //= {};
                    my $curres_hr     = $bw_hr->{$username};

                    $user_total_hr->{'total'} += $curres_hr->{'total'} // 0;

                    for my $domain ( keys %{ $curres_hr->{'by_domain'} } ) {
                        $user_total_hr->{'by_domain'}{$domain} += $curres_hr->{'by_domain'}{$domain};
                    }
                }
            }
        },
        values %node_promise,
    );

    return \%user_totals;
}

sub _get_all_cpusers() {
    require Cpanel::Config::Users;
    return Cpanel::Config::Users::getcpusers();
}

sub _lazy_load_forker ($forker_sr) {
    require Cpanel::Async::Forker;

    # Forker imports these, but require them directly
    # to keep cplint happy.
    require AnyEvent;
    require Promise::XS;

    $$forker_sr ||= Cpanel::Async::Forker->new();

    return;
}

sub _await ( $then_cr, @promises ) {
    if (@promises) {
        my $cv = AnyEvent->condvar();

        Promise::XS::all( values @promises )->then(
            sub (@usages) {
                $then_cr->(@usages);
                $cv->();
            }
        );

        $cv->recv();
    }

    return;
}

sub _fetch_remote_user_bw_in_child ( $node_obj, $username, $month, $year ) {
    my $data = _call_remote_showbw(
        $node_obj, $month, $year,
        searchtype => 'user',
        search     => $username,
    );

    return $data->{'acct'}[0]{'totalbytes'};
}

sub _fetch_all_remote_node_bw_in_child ( $node_obj, $month, $year ) {
    my $data = _call_remote_showbw( $node_obj, $month, $year );

    # We optimize what we send back to the parent node
    # in order to mimize the IPC overhead.
    return { map { @{$_}{ 'user', 'totalbytes' } } @{ $data->{'acct'} } };
}

sub _fetch_all_remote_node_bw_with_domains_in_child ( $node_obj, $month, $year ) {
    my $data = _call_remote_showbw( $node_obj, $month, $year );

    my %ret;

    for my $acct_hr ( @{ $data->{'acct'} } ) {
        my %domain_usage = map { @{$_}{ 'domain', 'usage' }; } @{ $acct_hr->{'bwusage'} };

        $ret{ $acct_hr->{'user'} } = {
            total     => $acct_hr->{'totalbytes'},
            by_domain => \%domain_usage,
        };
    }

    return \%ret;
}

sub _call_remote_showbw ( $node_obj, $month, $year, %xtra_args ) {    ## no critic qw(ManyArg) - mis-parse
    my $result;

    Cpanel::Try::try(
        sub {
            $result = Cpanel::LinkedNode::Worker::WHM::do_whmapi1_call(
                node_obj => $node_obj,
                function => 'showbw',
                api_opts => {
                    %xtra_args,
                    month => $month,
                    year  => $year,
                },
            );
        },
        q<> => sub ($err) { die Cpanel::Exception::get_string($err) },
    );

    return $result;
}

1;
