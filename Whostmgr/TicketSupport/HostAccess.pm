
# cpanel - Whostmgr/TicketSupport/HostAccess.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::TicketSupport::HostAccess;

use strict;

use base 'Whostmgr::TicketSupport::Whitelist';

use Cpanel::HostAccessLib ();
use Cpanel::Exception     ();

use Try::Tiny;

our $COMMENT = 'cPanel support access whitelist';

sub STATUS_NAME { return 'host_access_wl_status'; }

=head1 NAME

Whostmgr::TicketSupport::HostAccess

=head1 SYNOPSIS

  my $ha = Whostmgr::TicketSupport::HostAccess->new();
  $ha->setup();
  ...
  $ha->unsetup();


=head1 METHODS

=head2 Whostmgr::TicketSupport::HostAccess->new()

  The constructor accepts the following parameters:

=over 1

=item - access_ips | optional array ref | the list of IPs to allow (prevents remote API call from being sent)

=item - ssh_port | optional numeric value | the ssh port associated with the ticket+server in question

=back

=cut

sub new {
    my ( $package, @args ) = @_;
    my $self = $package->SUPER::new(@args);

    $self->{'hostaccess_obj'} = Cpanel::HostAccessLib->new();

    return $self;
}

=head2 $ha->setup

Add whitelist entries to hosts.allow for the cPanel support IP addresses.

=cut

sub setup {
    my ($self) = @_;

    my @clients = map { $_->{'ip'} } @{ $self->{'access_ips'} };

    $self->unsetup( quiet => 1 );    # Avoid duplication, but don't care if this fails

    $Whostmgr::TicketSupport::Whitelist::gl_logger->info("Setting up the cPanel Support hosts.allow entry…");

    my $success;
    eval {
        local $SIG{'__DIE__'};
        local $SIG{'__WARN__'};

        $self->{'hostaccess_obj'}->add(
            position    => 'top',
            daemon_list => ['sshd'],     # Note: The tcp wrap mechanism identifies sshd correctly even if it's running on a nonstandard port
            client_list => [@clients],
            action_list => ['ALLOW'],
            comment     => $COMMENT,
        );
        $self->{'hostaccess_obj'}->reserialize();
        $success = $self->{'hostaccess_obj'}->commit();
    };

    if ($@) {
        $Whostmgr::TicketSupport::Whitelist::gl_logger->warn("Failed to set up the cPanel Support hosts.allow entry: $@");
        return;
    }
    elsif ( !$success ) {
        $Whostmgr::TicketSupport::Whitelist::gl_logger->warn("Failed to set up the cPanel Support hosts.allow entry.");
        return;
    }

    return 1;
}

=head2 $ha->unsetup

Remove whitelist entries from hosts.allow for the cPanel support IP addresses.

=over 1

=item - quiet | optional boolean | don't complain if something about the removal fails

=back

=cut

sub unsetup {
    my ( $self, %opts ) = @_;

    $Whostmgr::TicketSupport::Whitelist::gl_logger->info("Removing the cPanel Support hosts.allow entry…") unless $opts{'quiet'};

    my $err;
    try {
        my $removed = $self->{'hostaccess_obj'}->remove_by_comment($COMMENT);
        die "No entries were found\n" if !$removed && !$opts{'quiet'};
        $self->{'hostaccess_obj'}->reserialize();
        $self->{'hostaccess_obj'}->commit();
    }
    catch {
        $err = $_;
    };

    if ($err) {
        my $err_as_string = Cpanel::Exception::get_string($err);

        $Whostmgr::TicketSupport::Whitelist::gl_logger->warn("Failed to remove the cPanel Support hosts.allow entry: $err_as_string") unless $opts{'quiet'};
        return;
    }
    return 1;
}

=head2 $ha->active

True if the hosts.allow whitelist entries for cPanel support IPs are present; otherwise false.

=cut

sub active {
    my ($self) = @_;

    return $self->{'hostaccess_obj'}->has_entry_with_comment($COMMENT);
}

=head2 $ha->should_skip

Whether to skip this module. If neither hosts.allow nor hosts.deny is present, then it can be
skipped since those files are clearly not being used.

=cut

sub should_skip {
    return ( !-f $Cpanel::HostAccessLib::HOSTS_ALLOW && !-f $Cpanel::HostAccessLib::HOSTS_DENY );
}

1;
