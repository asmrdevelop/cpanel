package Cpanel::TaskProcessors::LinkedNode;

# cpanel - Cpanel/TaskProcessors/LinkedNode.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::JSON                         ();
use Cpanel::LinkedNode::Alias::Constants ();    # PPI USE OK - Constants

=encoding utf-8

=head1 NAME

Cpanel::TaskProcessors::LinkedNode

=head1 DESCRIPTION

A set of task queue actions for linked node configuration changes.

=head1 SEE ALSO

L<Cpanel::TaskProcessors::ServerProfile>

=cut

#----------------------------------------------------------------------

# Avoid compile-time dependencies.

#----------------------------------------------------------------------

{

    package Cpanel::TaskProcessors::LinkedNode::PropagateHostnameUpdate;

    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub is_valid_args ( $self, $task, @ ) {
        my ( $alias, $old_hostname, @extra ) = $task->args();

        return 0 if !length $alias;
        return 0 if !length $old_hostname;
        return 0 if @extra;

        require Cpanel::LinkedNode::Index::Read;
        my $index_hr = Cpanel::LinkedNode::Index::Read::get();
        return 0 if !$index_hr->{$alias};

        return 1;
    }

    sub _do_child_task ( $self, $task, @ ) {
        require Cpanel::LinkedNode::HostnameUpdate;

        my ( $alias, $old_hostname ) = $task->args();

        Cpanel::LinkedNode::HostnameUpdate::propagate( $alias, $old_hostname );

        return;
    }
}

{

    package Cpanel::TaskProcessors::LinkedNode::AlterUserDistribution;

    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub is_valid_args {
        my ( $self, $task ) = @_;
        my $numargs = scalar $task->args();

        # Args count must be odd and >1.
        return 0 if $numargs < 2;
        return 0 if !( $numargs % 2 );

        return 1;
    }

    sub get_child_timeout {
        require Cpanel::Email::Constants;
        return Cpanel::Email::Constants::SYNC_TIMEOUT();
    }

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        my @args = $task->args();

        # We can’t do this in is_valid_args() because that runs in
        # queueprocd’s parent process.
        require Cpanel::LinkedNode::Convert;
        if ( !Cpanel::LinkedNode::Convert::convert_user_arguments_are_valid(@args) ) {
            die( __PACKAGE__ . ": Invalid args: @args" );
        }

        require Cpanel::LinkedNode::Convert;

        my ( $username, %worker_alias ) = @args;

        require Cpanel::Config::LoadCpUserFile;
        my $cpuser_data = Cpanel::Config::LoadCpUserFile::load_or_die($username);

        require Cpanel::LinkedNode::Worker::GetAll;
        my $old_user_child_nodes = Cpanel::LinkedNode::Worker::GetAll::get_lookup_from_cpuser($cpuser_data);

        require Cpanel::LinkedNode::Convert::Log;
        my $log_id = Cpanel::LinkedNode::Convert::Log->create_new( SUCCESS => 0 );

        Cpanel::LinkedNode::Convert::Log->redirect_stdout_and_stderr($log_id);

        my @log;
        my $log_cr = sub ( $type, $contents ) {
            push @log, [ $type, $contents ];

            # While unlikely, something could select away the default file handle on us, so
            # use STDOUT explicitly. We don’t distinguish between STDOUT and STDERR here because
            # they are both redirected to the process log.
            print STDOUT Cpanel::JSON::Dump( { type => $type, contents => $contents } ) . "\n";
        };

        local $ENV{'REMOTE_USER'} = 'root';

        require Whostmgr::ACLS;
        Whostmgr::ACLS::init_acls();

        my $succeeded = eval {
            Cpanel::LinkedNode::Convert::convert_user(
                $log_cr, $username, %worker_alias,
            );

            1;
        };

        _report_conversion( $username, !$succeeded && $@, \@log, \%worker_alias, $old_user_child_nodes );

        if ($succeeded) {
            Cpanel::LinkedNode::Convert::Log->set_metadata( $log_id, SUCCESS => $succeeded );
        }

        return;
    }

    sub _report_conversion {
        my ( $username, $err, $log_ar, $worker_alias, $old_user_child_nodes ) = @_;

        require Cpanel::Notify;

        my $notification_status = $err ? 'Failure' : 'Success';

        # The open ended hash from @args implies that worker_alias might be multiple worker types, so I'll loop this to accomodate
        foreach my $worker_type ( keys %$worker_alias ) {

            my $old_node_hr = $old_user_child_nodes->{$worker_type};

            my $notification_subtype;

            if ( $worker_alias->{$worker_type} eq Cpanel::LinkedNode::Alias::Constants::LOCAL ) {
                $notification_subtype = 'ChildDedistribution';
            }
            else {
                $notification_subtype = $old_node_hr ? 'ChildRedistribution' : 'ChildDistribution';
            }

            my $notification_type = "Accounts::$notification_subtype$notification_status";

            Cpanel::Notify::notification_class(
                'class'            => $notification_type,
                'application'      => $notification_type,
                'constructor_args' => [
                    user                => $username,
                    worker_type         => $worker_type,
                    worker_alias        => $worker_alias->{$worker_type},
                    old_alias           => $old_node_hr->{alias},
                    distribution_errors => [$err],
                ]
            );

        }

        return;
    }
}

=head1 FUNCTIONS

=head2 to_register()

As needed for interface.

=cut

sub to_register {
    return (
        [ 'alter_user_distribution',   Cpanel::TaskProcessors::LinkedNode::AlterUserDistribution->new() ],
        [ 'propagate_hostname_update', Cpanel::TaskProcessors::LinkedNode::PropagateHostnameUpdate->new() ],
    );
}

1;
