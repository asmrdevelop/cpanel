package Whostmgr::Quota;

# cpanel - Whostmgr/Quota.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Quota

=cut

#----------------------------------------------------------------------

use Cpanel::AcctUtils::Account ();
use Cpanel::CommandQueue       ();
use Cpanel::Debug              ();
use Cpanel::Exception          ();
use Cpanel::Quota::Constants   ();
use Cpanel::Validate::Integer  ();
use Whostmgr::ACLS             ();
use Whostmgr::AcctInfo::Owner  ();

use Try::Tiny;

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 ($status, $message) = setusersquota( $USERNAME, $QUOTA_MIB )

Synchronously sets $USERNAME’s quota to $QUOTA_MIB, which is either:

=over

=item * a positive number, in mebibytes

=item * 0, or the string C<unlimited>, to indicate no quota

=back

B<IMPORTANT:> This will B<synchronously> propagate the quota to
all of the user’s child nodes (if any).

The return is two-part: a boolean to indicate success, and the reason
for that state. (To accommodate legacy callers a 3rd value is returned
in certain instances, but this just duplicates the 2nd return.)

=cut

sub setusersquota ( $username, $quota_mib ) {
    my $msg;
    my $ok;

    $quota_mib = 0 if defined $quota_mib && $quota_mib eq 'unlimited';

    Cpanel::Validate::Integer::unsigned_and_less_than(
        $quota_mib,
        Cpanel::Quota::Constants::MAXIMUM_BLOCKS(),
    );

    if ( !Cpanel::AcctUtils::Account::accountexists($username) ) {
        $msg = 'Invalid user. Cannot set quota.';
    }
    elsif ( !Whostmgr::ACLS::hasroot() ) {
        if ( !Whostmgr::ACLS::checkacl('quota') ) {
            if ( !Whostmgr::ACLS::acls_are_initialized() ) {
                warn "ACLs aren’t yet initialized! Possible spurious authz failure …";
            }

            $msg = 'You do not have permission to modify quotas.';
        }
        elsif ( !Whostmgr::AcctInfo::Owner::checkowner( $ENV{'REMOTE_USER'}, $username ) ) {
            $msg = 'You do not own that account.';
        }
        else {
            require Whostmgr::Limits::Exceed;
            my ( $limit_would_be_exceeded, $limit_message ) = Whostmgr::Limits::Exceed::would_exceed_limit( 'disk', { 'user' => $username, 'nounlimited' => 1, 'newlimit' => $quota_mib } );

            $msg = $limit_message;
            $ok  = !$limit_would_be_exceeded;
        }
    }
    else {
        $ok = 1;
    }

    if ( !$ok ) {
        Cpanel::Debug::log_warn($msg);
        return 0, $msg;
    }

    #----------------------------------------------------------------------

    require Cpanel::Quota::Blocks;
    require Cpanel::Quota::Common;
    require Cpanel::Quota;

    my $blocks_obj = Cpanel::Quota::Blocks->new()->set_user($username);

    my ( $status, $message, $output );

    if ( $blocks_obj->quotas_are_enabled() ) {
        my $blocks = $quota_mib * $Cpanel::Quota::Common::MEGABYTES_TO_BLOCKS;

        my $old_limits = ( values %{ $blocks_obj->get_limits() } )[0]{'block'};

        my $cq = Cpanel::CommandQueue->new();

        $cq->add(
            sub {
                $blocks_obj->set_limits( { soft => $blocks, hard => $blocks } );
            },
            sub {
                $blocks_obj->set_limits($old_limits);

                # Propagate so that, if the quota-set failed on some
                # but not all of the remotes, we’ll attempt to restore
                # status quo ante on them all.
                _propagate_quota_as_needed( $username, $old_limits->{'hard'} );
            },
            'restoring & balancing old quota',
        );

        $cq->add(
            sub { _propagate_quota_as_needed( $username, $quota_mib ) },
        );

        try {
            $cq->run();
            ( $status, $message ) = ( 1, 'Set quota for user.' );
        }
        catch {
            $status = 0;
            $output = $message = Cpanel::Exception::get_string($_);
        };

        Cpanel::Quota::reset_cache($username);
    }
    else {
        ( $status, $message ) = ( 1, "Quotas are disabled." );
    }

    return $status, $message, $output;
}

sub _propagate_quota_as_needed ( $username, $quota_mib ) {
    if ($quota_mib) {
        _balance_distributed_account_quota($username);
    }
    else {
        _remove_distributed_account_quota($username);
    }

    return;
}

sub _remove_distributed_account_quota ($username) {
    require Cpanel::LinkedNode::Worker::WHM;
    Cpanel::LinkedNode::Worker::WHM::do_on_all_user_nodes(
        username      => $username,
        remote_action => sub ($node_obj) {
            $node_obj->get_remote_api()->request_whmapi1_or_die(
                'editquota',
                {
                    user  => $username,
                    quota => 0,
                },
            );
        },
    );

    return;
}

sub _balance_distributed_account_quota ($username) {
    my @errors;

    require Cpanel::Output::Callback;

    # These need not to be compiled until CPANEL-35700 is fixed.
    require Cpanel::LinkedNode::QuotaBalancer::Run;
    require Cpanel::PromiseUtils;

    my @ignore_types = qw( out success );

    my $output = Cpanel::Output::Callback->new(
        on_render => sub ($msg_hr) {
            my $contents = $msg_hr->{'contents'};

            if ( $msg_hr->{'type'} eq 'error' ) {
                push @errors, $contents;
            }
            elsif ( $msg_hr->{'type'} eq 'warn' ) {
                warn $contents;
            }

            # Ignore the informational ones …
            elsif ( !grep { $_ eq $msg_hr->{'type'} } @ignore_types ) {
                warn sprintf "%s: Message of unknown type (%s): %s", __PACKAGE__, @{$msg_hr}{ 'type', 'contents' };
            }
        },
    );

    my $runstate = Cpanel::LinkedNode::QuotaBalancer::Run::run_for_users(
        [$username],
        $output,
    );

    Cpanel::PromiseUtils::wait_anyevent( $runstate->get_promise() );

    die "@errors\n" if @errors;

    return;
}

1;
