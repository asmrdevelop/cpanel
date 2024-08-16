package Cpanel::TaskProcessors::DNSTasks;

# cpanel - Cpanel/TaskProcessors/DNSTasks.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

{

    package Cpanel::TaskProcessors::DNSTasks::RemoveZones;
    use parent 'Cpanel::TaskQueue::FastSpawn';
    use Cpanel::LoadModule ();

    #Make all dupes clobber the older task.
    *overrides = __PACKAGE__->can('is_dupe');

    sub is_valid_args {
        my ( $self, $task ) = @_;

        my @domains = $task->args();
        return undef if !scalar @domains;
        return undef if grep { index( $_, ',' ) > -1 } @domains;
        return 1;
    }

    sub _do_child_task {
        my ( $self, $task ) = @_;

        Cpanel::LoadModule::load_perl_module('Cpanel::DnsUtils::AskDnsAdmin');
        my @domains = $task->args();
        return Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( 'REMOVEZONES', 0, join( ',', @domains ) );
    }
}

{

    package Cpanel::TaskProcessors::DNSTasks::UpdateReverseDNSCache;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub _do_child_task {
        my ( $self, $task ) = @_;

        require Cpanel::Config::ReverseDnsCache::Update;
        return Cpanel::Config::ReverseDnsCache::Update::update_reverse_dns_cache();
    }

}

{

    package Cpanel::TaskProcessors::DNSTasks::VerifyDNSSECSync;

    use parent 'Cpanel::TaskQueue::FastSpawn';

    #Make all dupes clobber the older task.
    *overrides = __PACKAGE__->can('is_dupe');

    sub is_valid_args {
        my ( $self, $task ) = @_;
        return undef if $task->args();
        return 1;
    }

    sub _do_child_task {
        my ( $self, $task ) = @_;

        my @domain = $task->args();
        my $zone   = shift @domain;

        my @failed;

        require Cpanel::DNSLib::PeerConfig;
        require Cpanel::NameServer::DNSSEC::Verify;

        require Cpanel::DNSSEC::VerifyQueue::Harvester;

        my %verify_objs;
        foreach my $peer ( Cpanel::DNSLib::PeerConfig::getdnspeers() ) {
            $verify_objs{$peer} = Cpanel::NameServer::DNSSEC::Verify->new( nameserver => $peer );
        }

        my @zones;
        Cpanel::DNSSEC::VerifyQueue::Harvester->harvest(
            sub { push @zones, shift },
        );

        my %zones_with_failed_peers;
        foreach my $zone (@zones) {
            foreach my $peer ( sort keys %verify_objs ) {
                my $checks = $verify_objs{$peer}->check_dnssec($zone);
                if ( !$checks->{dnskey} || !$checks->{rrsig} ) {
                    push( @{ $zones_with_failed_peers{$zone} }, $peer );
                }
            }
        }

        return 1 if !scalar keys %zones_with_failed_peers;

        require Cpanel::Notify;
        foreach my $zone ( keys %zones_with_failed_peers ) {
            Cpanel::Notify::notification_class(
                'class'            => 'DnsAdmin::DnssecError',
                'application'      => 'DnsAdmin',
                'constructor_args' => [
                    'origin'            => 'DnsAdmin DNSSEC Sync Keys',
                    'source_ip_address' => $ENV{'REMOTE_ADDR'},
                    'zone'              => $zone,
                    'failed_peers'      => $zones_with_failed_peers{$zone},
                ]
            );
        }

        return 1;

    }

}

{

    package Cpanel::TaskProcessors::DNSTasks::BuildDNSSECCache;

    use parent 'Cpanel::TaskQueue::FastSpawn';

    #Make all dupes clobber the older task.
    *overrides = __PACKAGE__->can('is_dupe');

    sub is_valid_args {
        my ( $self, $task ) = @_;
        return 1;    # no args
    }

    sub _do_child_task {
        my ( $self, $task ) = @_;
        require Cpanel::NameServer::DNSSEC::Cache;
        Cpanel::NameServer::DNSSEC::Cache::rebuild_cache();
        return 1;
    }
}

{

    package Cpanel::TaskProcessors::DNSTasks::SetupResolverWorkarounds;

    use parent 'Cpanel::TaskQueue::FastSpawn';

    #Make all dupes clobber the older task.
    *overrides = __PACKAGE__->can('is_dupe');

    sub is_valid_args {
        my ( $self, $task ) = @_;
        return 1;    # no args
    }

    sub _do_child_task {
        my ( $self, $task ) = @_;
        require Cpanel::DNS::Unbound::Workarounds;
        Cpanel::DNS::Unbound::Workarounds::set_up_dns_resolver_workarounds();
        return 1;
    }
}

sub to_register {
    return (
        [ 'update_reverse_dns_cache',        Cpanel::TaskProcessors::DNSTasks::UpdateReverseDNSCache->new() ],
        [ 'remove_zones',                    Cpanel::TaskProcessors::DNSTasks::RemoveZones->new() ],
        [ 'verify_dnssec_sync',              Cpanel::TaskProcessors::DNSTasks::VerifyDNSSECSync->new() ],
        [ 'build_dnssec_cache',              Cpanel::TaskProcessors::DNSTasks::BuildDNSSECCache->new() ],
        [ 'set_up_dns_resolver_workarounds', Cpanel::TaskProcessors::DNSTasks::SetupResolverWorkarounds->new() ],
    );
}

1;
__END__

=encoding utf-8

=head1 NAME

Cpanel::TaskProcessors::DNSTasks - Task processor for restarting DNS

=head1 VERSION

This document describes Cpanel::TaskProcessors::DNSTasks version 0.0.3


=head1 SYNOPSIS

    use Cpanel::TaskProcessors::DNSTasks;

=head1 DESCRIPTION

Implement the code for the I<RemoveZones> Tasks. These
are not intended to be used directly.

=head1 INTERFACE

This module defines two subclasses of L<Cpanel::TaskQueue::FastSpawn> and a package method.

=head2 Cpanel::TaskProcessors::DNSTasks::to_register

Used by the L<Cpanel::TaskQueue::PluginManager> to register the included classes.

=over

=item $proc->is_valid_args( $task )

Validates the number of arguments for the remove_zones call

=back

=head2 Cpanel::TaskProcessors::DNSTasks::RemoveZones

Calls Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin to remove one or more zones.

=head1 CONFIGURATION AND ENVIRONMENT

Cpanel::TaskProcessors::DNSTasks assumes that the environment has been made
safe before any of the tasks are executed.

=head1 DEPENDENCIES

None

=head1 INCOMPATIBILITIES

None reported.
