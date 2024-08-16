package Cpanel::TaskProcessors::DNSAdminTasks;

# cpanel - Cpanel/TaskProcessors/DNSAdminTasks.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

{

    package Cpanel::TaskProcessors::DNSAdminTasks::Clustercache;

    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub overrides {
        my ( $self, $new, $old ) = @_;
        my $is_dupe = $self->is_dupe( $new, $old );
        return $is_dupe;
    }

    #no args
    sub is_valid_args {
        my ( $self, $task ) = @_;
        my $numargs = scalar $task->args();
        return 0 if $numargs != 1;
        my ($user) = $task->args();
        return 0 unless $user;
        require Cpanel::Autodie::More::Lite;
        return 0 unless Cpanel::Autodie::More::Lite::exists("/var/cpanel/cluster/$user");
        return 1;
    }

    sub _do_child_task {
        my ( $self, $task ) = @_;
        my ($user) = $task->args();
        require Cpanel::DNSLib::PeerStatus;
        local $ENV{REMOTE_USER} = $user;
        return Cpanel::DNSLib::PeerStatus::getclusterstatus(1);
    }

}

{

    package Cpanel::TaskProcessors::DNSAdminTasks::Synczones;

    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub overrides {
        my ( $self, $new, $old ) = @_;
        my $is_dupe = $self->is_dupe( $new, $old );
        return $is_dupe;
    }

    #no args
    sub is_valid_args {
        return 1;
    }

    sub _do_child_task {
        my ( $self, $task ) = @_;
        require Cpanel::DnsUtils::Sync;
        return Cpanel::DnsUtils::Sync::sync_zones();
    }

}

{

    package Cpanel::TaskProcessors::DNSAdminTasks::Synckeys;

    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub overrides {
        my ( $self, $new, $old ) = @_;
        my $is_dupe = $self->is_dupe( $new, $old );
        return $is_dupe;
    }

    sub is_valid_args {
        my ( $self, $task ) = @_;

        # args must come through the harvester
        return undef if $task->args();
        return 1;
    }

    sub _do_child_task {
        my ( $self, $task ) = @_;

        require Cpanel::NameServer::DNSSEC::SyncKeys;
        require Cpanel::NameServer::DNSSEC::SyncKeys::Harvester;

        my %tasks;
        Cpanel::NameServer::DNSSEC::SyncKeys::Harvester->harvest(
            sub {
                my $id   = shift;
                my $opts = shift;
                return if !$id || !$opts;
                $tasks{$id} = $opts;
            },
        );

        my %jobs;
        foreach my $id ( keys %tasks ) {
            my $domain = $tasks{$id}->{domain};
            my $action = $tasks{$id}->{action};
            my $tag    = $tasks{$id}->{keytag};

            next if !$domain;
            next if $action ne 'sync' && $action ne 'revoke';
            next if $tag !~ /[0-9]+/;
            push( @{ $jobs{$domain}{$action} }, $tag );
        }

        foreach my $domain ( keys %jobs ) {
            my $cluster = Cpanel::NameServer::DNSSEC::SyncKeys->new($domain);
            if ( $jobs{$domain}{sync} ) {
                $cluster->sync_keys( $jobs{$domain}{sync} );
            }
            if ( $jobs{$domain}{revoke} ) {
                $cluster->revoke_keys( $jobs{$domain}{revoke} );
            }

        }

        return 1;
    }
}

sub to_register {
    return (
        [ 'synczones',    Cpanel::TaskProcessors::DNSAdminTasks::Synczones->new() ],
        [ 'synckeys',     Cpanel::TaskProcessors::DNSAdminTasks::Synckeys->new() ],
        [ 'clustercache', Cpanel::TaskProcessors::DNSAdminTasks::Clustercache->new() ],
    );
}

1;
__END__


=head1 NAME

Cpanel::TaskProcessors::DNSAdminTasks

=head2 DESCRIPTION

Essentially a matroshka like all the TaskProcessors, it contains other modules.  In this case, only one -- Synczones.

=head1 SYNOPSIS

    require Cpanel::ServerTasks;
    Cpanel::ServerTasks::queue_task( ['DNSAdminTasks'], "synczones" );

=head1 Cpanel::TaskProcessors::DNSAdminTasks::Synczones

=head2 to_register()

To be honest, not really sure why these aren't defined as constants so I don't have to document this for POD coverage.
This probably could be defined in the parent module for 99% of use cases.

=head2 overrides()

Makes sure the tasks-dedup correctly.  Not sure why this isn't the default in the parent module.

=head2 is_valid_args()

Stub, we have no args.
