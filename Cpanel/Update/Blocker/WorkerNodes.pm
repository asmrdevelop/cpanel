package Cpanel::Update::Blocker::WorkerNodes;

# cpanel - Cpanel/Update/Blocker/WorkerNodes.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Update::Blocker::WorkerNodes

=head1 SYNOPSIS

    my $why = Cpanel::Update::Blocker::WorkerNodes::get_workers_problem(
        logger => $logger_obj,
        target_version => '11.94.0.3',
    );

=head1 DESCRIPTION

This module houses logic for interrogating child nodes as part of
upcp blocker checks.

=cut

#----------------------------------------------------------------------

use Cpanel::Imports;

use Cpanel::Exception               ();
use Cpanel::LinkedNode::Index::Read ();
use Cpanel::PromiseUtils            ();
use Cpanel::Version::Compare        ();

# We normally lazy-load these, but for perlpkg we load them explicitly.
use cPanel::APIClient                             ();
use cPanel::APIClient::Service::whm               ();
use cPanel::APIClient::Request::WHM1              ();
use cPanel::APIClient::Transport::NetCurlPromiser ();
use Net::Curl::Promiser::AnyEvent                 ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $why = get_workers_problem( %ARGS )

Returns a string that summarizes any worker-node-related impediments.
Details are reported to the passed logger object.

%ARGS are:

=over

=item * C<logger> - A L<Cpanel::Logger> instance. This will receive details
of any reported error(s).

=item * C<target_version> - The target version (e.g., C<11.94.0.3>) for the
cPanel & WHM update.

=back

=cut

sub get_workers_problem (%opts) {

    my $logger = $opts{'logger'} or die "need logger";

    my $target_version = $opts{'target_version'} or die "need target_version";

    if ( $target_version !~ tr<.><> ) {
        die "invalid “target_version” ($target_version)!";
    }

    my $target_major_version = Cpanel::Version::Compare::get_major_release($target_version);

    my $nodes_hr = Cpanel::LinkedNode::Index::Read::get();

    my @promises;

    my %update_working;

    my @check_failed;

    my $log_err = sub ($phrase) {
        $logger->error($phrase);
    };

    foreach my $node_obj ( values %$nodes_hr ) {
        my $api      = $node_obj->get_async_remote_api();
        my $hostname = $node_obj->hostname();

        push @promises, $api->request_whmapi1('version')->then(
            sub ($res) {
                my $remote_version = $res->get_data()->{'version'} or do {
                    die "No version in $hostname’s `version` API response!\n";
                };

                my $remote_major_version = Cpanel::Version::Compare::get_major_release($remote_version);

                if ( Cpanel::Version::Compare::compare( $remote_major_version, '<', $target_major_version ) ) {
                    $log_err->("“$hostname” runs cPanel & WHM version $remote_version.  This update’s target version is $target_version. All child nodes must be up to date before this server can update. The system will now attempt to start an update on “$hostname”.");

                    my $update_sr = \$update_working{$hostname};

                    return _update_promise( $logger, $hostname, $api, $update_sr );
                }
            },
        )->catch(
            sub ($why) {
                push @check_failed, $hostname;

                # We don’t need a stack trace …
                $why = Cpanel::Exception::get_string($why);

                $log_err->("The system failed to determine “$hostname”’s cPanel & WHM version because of an error: $why");
            },
        );
    }

    # No need to get() the results here since all errors are trapped above.
    Cpanel::PromiseUtils::wait_anyevent(@promises) if @promises;

    return _get_report( \@check_failed, \%update_working, $target_major_version );
}

sub _get_report ( $check_failed_ar, $update_working_hr, $target_major_version ) {    ## no critic qw(ProhibitManyArgs) - mis-parse
    my $automatic_updates = grep { $update_working_hr->{$_} } keys %$update_working_hr;

    my $needs_manual_work = keys(%$update_working_hr) - $automatic_updates;
    $needs_manual_work += @$check_failed_ar;

    my @phrases;

    if ($needs_manual_work) {
        $needs_manual_work == 1
          ? push @phrases, "child node requires manual attention.\n"
          : push @phrases, "child nodes require manual attention.\n";
    }

    if ($automatic_updates) {
        $automatic_updates == 1
          ? push @phrases, "child node is automatically updating.\n"
          : push @phrases, "child nodes are automatically updating.\n";
    }

    if (@phrases) {
        my $total_nodes = $needs_manual_work + $automatic_updates;
        $total_nodes == 1
          ? push @phrases, "Try again once this child node runs version $target_major_version or later.\n"
          : push @phrases, "Try again once all child nodes run version $target_major_version or later.\n";
    }

    return "@phrases";
}

sub _update_promise ( $logger, $hostname, $api, $update_sr ) {
    return $api->request_whmapi1('start_cpanel_update')->then(
        sub ($resp) {
            $$update_sr = 1;

            my ( $new_yn, $pid, $log_path ) = @{ $resp->get_data() }{ 'is_new', 'pid', 'log_path' };

            my @phrases;

            if ($new_yn) {
                push @phrases, "An update on “$hostname” (process ID: $pid) is now in progress.\n";
            }
            else {
                push @phrases, "There is already a version update in progress on “$hostname” (process ID: $pid )\n";
            }

            push @phrases, "The update’s log file on that system is “$log_path”.\n";

            $logger->info("@phrases");
        },
        sub ($why) {
            $$update_sr = 0;

            my $why_string = Cpanel::Exception::get_string($why);
            $logger->warn("The system failed to start a cPanel & WHM update on “$hostname” because of an error: $why_string");
        },
    );
}

1;
