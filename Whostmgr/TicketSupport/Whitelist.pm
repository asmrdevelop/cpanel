
# cpanel - Whostmgr/TicketSupport/Whitelist.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::TicketSupport::Whitelist;

use strict;

use Cpanel::DIp::MainIP                ();
use Whostmgr::TicketSupport::DataStore ();
use Cpanel::Logger                     ();
use Cpanel::SafeFile                   ();
use Whostmgr::TicketSupport            ();

our $gl_logger;
our $gl_local_authorizations_list;

=head1 NAME

Whostmgr::TicketSupport::Whitelist

=head1 SYNOPSIS

use base 'Whostmgr::TicketSupport::Whitelist';

=head1 METHODS PROVIDED

=head2 ...->new()

=over 1

=item - access_ips

=item - logger

=back

=cut

sub new {
    my ( $package, @args ) = @_;
    my $self = {@args};
    bless $self, $package;

    # this can be shared between all instances #
    $gl_logger ||= Cpanel::Logger->new();

    # Best to avoid re-fetching this if it can be helped, since it causes a JSON query to be sent remotely
    $self->{'access_ips'} ||= ( Whostmgr::TicketSupport::access_ips() || die("Could not retrieve access IPs!") );
    $self->{'mainserverip'} = Cpanel::DIp::MainIP::getmainserverip() || die("Couldn't determine my own IP address!");

    my $type = ( $package =~ /::(\w+)$/ )[0] || 'whitelist';
    $self->{'lock'}  = Cpanel::SafeFile::safelock("/var/run/ticketsupport-$type-lock");
    $self->{'store'} = Whostmgr::TicketSupport::DataStore->new();

    return $self;
}

=head2 $obj->still_needed

Returns a boolean value indicating whether the temporary configuration in question is
still needed, based on whether any tickets remain for which this server (not some
other server on the ticket) is in AUTHED state.

=cut

sub still_needed {
    my ($self) = @_;
    my $gl_local_authorizations_list ||= Whostmgr::TicketSupport::local_authorizations_list( undef, undef, $self->{'store'} );

    for my $ticket ( values %{$gl_local_authorizations_list} ) {
        for my $server ( values %{ $ticket->{'servers'} } ) {
            return 1 if $server->{'auth_time'};
        }
    }
    return;
}

sub finish {
    my ($self) = @_;

    # release the data store #
    $self->{'store'}->cleanup();
    delete $self->{'store'};

    # release the lock #
    Cpanel::SafeFile::safeunlock( $self->{'lock'} );
    delete $self->{'lock'};

    return $self;
}

sub should_skip { return }

=head1 METHODS TO BE IMPLEMENTED BY SUBCLASSS

=head2 $obj->setup()

Must be implemented by subclass -- set up the whitelist.

=head2 $obj->unsetup()

Must be implemented by subclass -- remove the whitelist.

=head2 $obj->active()

Must be implemented by subclass -- check whether the whitelist is active.

=head2 $obj->STATUS_NAME()

Must be implemented by subclass -- the name of the status item to return
in the grant and revoke API calls.

=cut

sub setup   { die }
sub unsetup { die }
sub active  { die }

sub DESTROY {
    my ($self) = @_;

    if ( $self->{'lock'} ) {
        warn __PACKAGE__ . ": object destroyed without releasing lock";
        $self->finish();
    }
    return;
}
1;
