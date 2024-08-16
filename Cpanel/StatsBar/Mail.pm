package Cpanel::StatsBar::Mail;

# cpanel - Cpanel/StatsBar/Mail.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::StatsBar::Worker

=head1 SYNOPSIS

    my $stats_obj = Cpanel::StatsBar::Mail::create();

=head1 DESCRIPTION

This module implements the StatsBar’s fetch of data for mail-type
data, which can, depending on whether the user has a C<Mail> worker
configured, be gathered locally or remotely.

=cut

#----------------------------------------------------------------------

use Cpanel::LinkedNode::Worker::User ();
use Cpanel::Quota                    ();

# These are stored as JSON strings rather than as Perl arrays
# in order to save the expense of serialization.
use constant _BATCH_ARGS => {
    'command-0' => '[ "Email", "count_pops", { "no_validate":1 } ]',
    'command-1' => '[ "Email", "count_auto_responders" ]',
    'command-2' => '[ "Email", "count_forwarders" ]',
    'command-3' => '[ "Email", "count_lists" ]',
    'command-4' => '[ "Email", "get_lists_total_disk_usage" ]',
    'command-5' => '[ "Email", "count_filters" ]',

    # We’re going to need a better plan when we add additional node types
    # and accommodate use cases where we may need a user’s disk usage from
    # multiple remotes at once. But this satisifes the need for v88. See
    # COBRA-11012 for the follow-up work.
    'command-6' => '[ "Quota", "get_local_quota_info" ]',
};

my $locale;

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $accessor_obj = create()

Returns an accessor object that implements the following methods:

=over

=item * C<get_pops_count()>

=item * C<get_autoresponders_count()>

=item * C<get_forwarders_count()>

=item * C<get_lists_count()>

=item * C<get_lists_disk_usage()> (i.e., total disk usage for all lists)

=item * C<get_filters_count()>

=item * C<get_total_bytes_used()> (i.e., total of local & Mail child,
including non-mail disk usage)

=back

=cut

sub create {
    my $result = Cpanel::LinkedNode::Worker::User::call_worker_uapi(
        'Mail',
        Batch => 'strict',
        _BATCH_ARGS(),
    );

    my $ar;

    if ($result) {
        if ( $result->status() ) {
            my @warns = map { @{ $result->$_() // [] } } qw( errors warnings );
            warn( __PACKAGE__ . " remote batch API: $_" ) for @warns;

            my @result;

            for my $this ( @{ $result->data() } ) {

                # Convey relevant errors and warnings. There ordinarily
                # aren’t “errors” in successful UAPI call responses,
                # but it’s possible, so let’s look for it.
                my @warns = map { @{ $this->{$_} // [] } } qw( errors warnings );
                for my $msg (@warns) {
                    my $call = _BATCH_ARGS()->{ 'command-' . @result };
                    warn "$call: $msg\n";
                }

                # TODO: It might be ideal if batch API call responses were
                # “aware” that they are responses to batch calls and returned
                # an array reference of Cpanel::Result objects accordingly.
                push @result, $this->{'data'};
            }

            $ar = \@result;
        }
        else {
            require Cpanel::Locale;
            $locale ||= Cpanel::Locale::lh();    # no args uses $Cpanel::CPDATA{'LANG'};
            my $error_str = $locale->maketext( "Remote [asis,API] call to fetch mail statistics failed: [_1]", $result->errors_as_string() );
            my $error_fn  = sub { die $error_str };
            $ar = [
                $error_fn,
                $error_fn,
                $error_fn,
                $error_fn,
                $error_fn,
                $error_fn,
                $error_fn,
            ];
        }
    }
    else {
        $ar = [
            sub {
                require Cpanel::Email::Count;
                return Cpanel::Email::Count::count_pops( no_validate => 1 );
            },
            sub {
                require Cpanel::Email::Autoresponders;
                return Cpanel::Email::Autoresponders::count();
            },
            sub {
                require Cpanel::Email::Forwarders;
                return Cpanel::Email::Forwarders::count();
            },
            sub {
                require Cpanel::Email::Lists;
                return ( 0 + Cpanel::Email::Lists::get_names() );
            },
            sub {
                require Cpanel::Email::Lists;
                return Cpanel::Email::Lists::get_total_disk_usage();
            },
            sub {
                require Cpanel::Email::Filter;
                return Cpanel::Email::Filter::countfilters();
            },
            sub { return { bytes_used => 0 } },
        ];
    }

    return bless $ar, ( __PACKAGE__ . '::_ACCESSOR' );
}

#----------------------------------------------------------------------

package Cpanel::StatsBar::Mail::_ACCESSOR;

sub get_pops_count {
    $_[0][0] = $_[0][0]->() if ref $_[0][0];
    return $_[0][0];
}

sub get_autoresponders_count {
    $_[0][1] = $_[0][1]->() if ref $_[0][1];
    return $_[0][1];
}

sub get_forwarders_count {
    $_[0][2] = $_[0][2]->() if ref $_[0][2];
    return $_[0][2];
}

sub get_lists_count {
    $_[0][3] = $_[0][3]->() if ref $_[0][3];
    return $_[0][3];
}

sub get_lists_disk_usage {
    $_[0][4] = $_[0][4]->() if ref $_[0][4];
    return $_[0][4];
}

sub get_filters_count {
    $_[0][5] = $_[0][5]->() if ref $_[0][5];
    return $_[0][5];
}

sub get_total_bytes_used {
    $_[0][6] = $_[0][6]->() if 'CODE' eq ref $_[0][6];

    my $local = Cpanel::Quota::_getspaceused_bytes();
    $local = 0 if 0 == rindex( $local, 'NA', 0 );

    return $local + $_[0][6]->{'bytes_used'};
}

1;
