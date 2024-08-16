package Cpanel::LinkedNode::Convert;

# cpanel - Cpanel/LinkedNode/Convert.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Try::Tiny;

use Cpanel::Exception                    ();
use Cpanel::LinkedNode::Alias::Constants ();    # PPI USE OK - Constants
use Cpanel::LoadModule                   ();

use Cpanel::Imports;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::Convert

=head1 SYNOPSIS

    my $ok = Cpanel::LinkedNode::Convert::convert_user_arguments_are_valid(
        'bob',
        Mail => 'themailalias',
    );

=head1 DESCRIPTION

This module implements logic for manipulating users’ distributed-workload
configuration.

=cut

#----------------------------------------------------------------------

# NB: Dependencies are kept light here so that this module can be
# use()d within Cpanel::TaskProcessors::LinkedNode.

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $yn = convert_user_arguments_are_valid ($USERNAME, %WORKER_ALIAS)

Returns a boolean that indicates that the given arguments are
valid for C<convert_user()>, minus the log callback argument.

=cut

sub convert_user_arguments_are_valid ( $username, %worker_alias ) {
    local ( $@, $! );

    return 0 if !%worker_alias;

    require Cpanel::AcctUtils::Account;
    return 0 if !Cpanel::AcctUtils::Account::accountexists($username);

    # We don’t need to verify that the account isn’t already distributed
    # because it’s the same account backup regardless.

    require Cpanel::LinkedNode::Alias;
    require Cpanel::LinkedNode::User;
    require Cpanel::LinkedNode::Worker::GetAll;

    my @known_worker_types = Cpanel::LinkedNode::Worker::GetAll::RECOGNIZED_WORKER_TYPES();

    for my $worker_type ( keys %worker_alias ) {
        return 0 if !grep { $_ eq $worker_type } @known_worker_types;

        my $worker_alias = $worker_alias{$worker_type};
        my $is_local     = $worker_alias eq Cpanel::LinkedNode::Alias::Constants::LOCAL;

        # Reject invalid alias.
        return 0 if !$is_local && !eval {
            Cpanel::LinkedNode::Alias::validate_linked_node_alias_or_die($worker_alias);
            1;
        };

        # Reject valid-but-nonexistent alias.
        if ( !$is_local && !Cpanel::LinkedNode::User::get_node_configuration_if_exists($worker_alias) ) {
            return 0;
        }
    }

    return 1;
}

=head2 convert_user( $ON_LOG_CR, $USERNAME, %WORKER_ALIAS )

Converts a single cPanel account’s workload-distribution status.

$ON_LOG_CR is a callback that fires on every log message. It receives
two arguments each time: the log level, and the message. (Both are strings).
Possible log levels are as used in L<Cpanel::Output>.

$USERNAME is the name of the user to convert. %WORKER_ALIAS uses worker
types (e.g., C<Mail>) as keys and worker aliases as values.

The special alias Cpanel::LinkedNode::Alias::Constants::LOCAL as a value
of %WORKER_ALIAS indicates that the local server should fulfill that
functionality. This is how you can “de-distribute” a given workload for
an account (i.e., have the local server rather than a child node implement
the relevant functionality).

For example:

    convert_user(
        sub { .. }, 'johnny',
        Mail => 'mailnode',
        Web => Cpanel::LinkedNode::Alias::Constants::LOCAL,
    );

… means to serve C<johnny>’s mail on a child node whose alias is C<mailnode>
and to serve that user’s web content locally. (NB: C<Web> doesn’t actually
work as of v94; only C<Mail> does.)

This throws an exception on failure and tries to roll back any changes
that may have taken place before the failure.

=cut

sub convert_user ( $log_cr, $username, %worker_alias ) {
    local ( $@, $! );

    require Cpanel::Output::Callback;
    require Cpanel::CommandQueue;
    require Cpanel::LinkedNode::Convert::Mutex;
    require Cpanel::LoadModule;

    my $output_obj = Cpanel::Output::Callback->new(
        on_render => sub ($msg_hr) {
            $log_cr->( @{$msg_hr}{ 'type', 'contents' } );
        },
    );

    my @commands;

    for my $worker_type ( sort keys %worker_alias ) {

        my $direction;

        if ( $worker_alias{$worker_type} eq Cpanel::LinkedNode::Alias::Constants::LOCAL ) {
            $direction = 'FromDistributed';
        }
        else {

            require Cpanel::Config::LoadCpUserFile;
            my $cpuser_data = Cpanel::Config::LoadCpUserFile::load_or_die($username);

            require Cpanel::LinkedNode::Worker::GetAll;
            my $existing_node_hr = Cpanel::LinkedNode::Worker::GetAll::get_one_from_cpuser( $worker_type, $cpuser_data );
            my $existing_alias   = $existing_node_hr->{alias} if $existing_node_hr;

            $direction = $existing_alias ? 'CrossDistributed' : 'ToDistributed';

        }

        my $module_name = "Cpanel::LinkedNode::Convert::${direction}::$worker_type";

        Cpanel::LoadModule::load_perl_module($module_name);

        my $convert_cr = $module_name->can('convert');

        push @commands, sub {
            $convert_cr->(
                username     => $username,
                worker_alias => $worker_alias{$worker_type},
                output_obj   => $output_obj,
            );
        };

    }

    _do_under_mutex( $username, @commands );

    return;
}

=head2 $user_workloads_ar = force_dedistribution_from_node( $OUTPUT_OBJ, $WORKER_ALIAS, \@USERNAMES )

“Forgets” the indicated child node locally. Updates DNS as needed at the
end in a single batch.

The return is a reference to an array of hashrefs, each of which is:

=over

=item * C<username>

=item * C<workloads> - an array of strings (e.g., C<Mail>)

=back

B<NOTE:> The messages sent to $OUTPUT_OBJ will include icons that
more or less assume plain-text output. If these messages might be
rendered in, e.g., HTML or some other “fancier” context, it would
be suitable to strip those icons prior to sending them to that other
context. See L<Cpanel::TaskRunner::Icons>.

=cut

sub force_dedistribution_from_node ( $output_obj, $worker_alias, $users_ar ) {    ## no critic qw(ManyArgs) - mis-parse

    local ( $@, $! );

    _validate_force_dedistribute_inputs( $worker_alias, $users_ar );

    require Cpanel::CommandQueue;
    require Cpanel::LinkedNode::Convert::Mutex;

    my $results_ar = [];

    require Cpanel::LinkedNode::List;
    my $user_workers_ar = Cpanel::LinkedNode::List::list_user_worker_nodes();

    my ( %user_workloads, %workload_module );

    for my $user_worker_hr (@$user_workers_ar) {
        next if $user_worker_hr->{alias} ne $worker_alias;

        my ( $username, $workload ) = @{$user_worker_hr}{ 'user', 'type' };

        if ( grep { $_ eq $username } @$users_ar ) {

            $workload_module{$workload} ||= do {
                my $modname = "Cpanel::LinkedNode::Convert::FromDistributed::$workload";
                Cpanel::LoadModule::load_perl_module($modname);
            };

            push @{ $user_workloads{$username} }, $workload;
        }

    }

    my @nondistributed = grep { !$user_workloads{$_} } @$users_ar;

    if (@nondistributed) {
        die "Non-user(s) of “$worker_alias”: @nondistributed";
    }

    my @dns_updates;

    foreach my $username ( sort keys %user_workloads ) {

        my @commands;

        foreach my $conversion_type ( @{ $user_workloads{$username} } ) {
            my $module_name = $workload_module{$conversion_type};
            my $convert_cr  = $module_name->can('local_convert');

            push @commands, sub {
                $output_obj->info( locale()->maketext( 'Converting “[_1]” …', $username ) );
                my $indent = $output_obj->create_indent_guard();

                try {
                    my $these_dns_updates_ar = $convert_cr->(
                        username     => $username,
                        worker_alias => $worker_alias,
                        output_obj   => $output_obj,
                    );

                    push @dns_updates, @$these_dns_updates_ar;
                }
                catch {
                    $output_obj->error( Cpanel::Exception::get_string($_) );
                };
            };
        }

        _do_under_mutex( $username, @commands );

        push @$results_ar, {
            username  => $username,
            workloads => $user_workloads{$username},
        };
    }

    if (@dns_updates) {
        $output_obj->info( locale()->maketext('Updating [asis,DNS] …') );
        my $indent = $output_obj->create_indent_guard();

        try {
            require Cpanel::DnsUtils::Batch;
            Cpanel::DnsUtils::Batch::set( \@dns_updates );

            $output_obj->success('Success!');
        }
        catch {
            $output_obj->error( Cpanel::Exception::get_string($_) );
        };
    }

    return $results_ar;
}

sub _validate_force_dedistribute_inputs ( $worker_alias, $users_ar ) {

    require Cpanel::AcctUtils::Account;

    my @nonexist = grep { !Cpanel::AcctUtils::Account::accountexists($_) } @$users_ar;

    if (@nonexist) {
        require Carp;
        Carp::croak("Nonexistent user(s): @nonexist");
    }

    return;
}

sub _do_under_mutex ( $username, @commands ) {

    my $cq = Cpanel::CommandQueue->new();

    my $mutex;

    $cq->add(
        sub {
            $mutex = Cpanel::LinkedNode::Convert::Mutex->new_if_not_exists($username);
            die locale()->maketext( "The system is already performing an account conversion for “[_1]”.", $username ) if !$mutex;
        },
    );

    $cq->add($_) for @commands;

    $cq->run();

    return;
}

1;
