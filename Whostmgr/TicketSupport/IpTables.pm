
# cpanel - Whostmgr/TicketSupport/IpTables.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::TicketSupport::IpTables;

use strict;
use warnings;

use base 'Whostmgr::TicketSupport::Whitelist';

use Cpanel::XTables::Whitelist ();
use Cpanel::Exception          ();

use Try::Tiny;

=head1 NAME

Whostmgr::TicketSupport::IpTables

=head1 SYNOPSIS

  # Install the chain and make it active
  sub ......... {
      my $ipt = Whostmgr::TicketSupport::IpTables->new();
      $ipt->setup();
  }

  # Deactivate and remove the chain
  sub ......... {
      my $ipt = Whostmgr::TicketSupport::IpTables->new();
      $ipt->unsetup();
  }

=head1 METHODS

=head2 Whostmgr::TicketSupport::IpTables->new()

  The constructor accepts the following parameters:

=over 1

=item - access_ips | optional array ref | the list of IPs to allow (prevents remote API call from being sent)

=item - ssh_port | optional numeric value | the ssh port associated with the ticket+server in question

=back

=cut

sub new {
    my ( $package, @args ) = @_;
    my $self = $package->SUPER::new(@args);

    $self->{'iptables_obj'} = Cpanel::XTables::Whitelist->new( 'chain' => CHAIN_NAME() );
    $self->{'iptables_obj'}->ipversion(4);

    return $self;
}

#### constants ####

sub CHAIN_NAME  { return 'cPanel-support-access' }
sub STATUS_NAME { return 'chain_status' }

#### methods ####

=head2 $ipt->setup

Install and activate an iptables chain to allow cPanel support IPs access
into this server. The caller is responsible for determining whether this
is a good idea.

=cut

sub setup {
    my ($self) = @_;

    my @ips = map { $_->{'ip'} } @{ $self->{'access_ips'} };

    $self->unsetup( quiet => 1 );    # Avoid duplication, but don't care if this fails

    $Whostmgr::TicketSupport::Whitelist::gl_logger->info("Setting up cPanel support access iptables chain");

    eval {
        local $SIG{'__DIE__'};
        local $SIG{'__WARN__'};

        $self->{'iptables_obj'}->clear_ruleset_cache();
        $self->{'iptables_obj'}->init_chain();
        for my $ip (@ips) {
            $self->{'iptables_obj'}->accept_in_both_directions($ip);
        }
        $self->{'iptables_obj'}->attach_chain('INPUT');
        $self->{'iptables_obj'}->attach_chain('OUTPUT');
    };
    if ($@) {
        $Whostmgr::TicketSupport::Whitelist::gl_logger->warn("Failed to set up cPanel support access iptables chain: $@");
        return;
    }
    return 1;
}

=head2 $ipt->unsetup

Deactivate and remove the iptables chain, if any, that allows cPanel support
access into this server. The caller is responsible for determining whether
this is a good idea.

=over 1

=item - quiet | optional boolean | don't complain if something about the removal fails (including the chain being missing in the first place)

=back

=cut

sub unsetup {
    my ( $self, %opts ) = @_;

    $Whostmgr::TicketSupport::Whitelist::gl_logger->info("Removing cPanel support access iptables chain") unless $opts{'quiet'};

    my $err;
    try {
        $self->{'iptables_obj'}->purge_chain();
        $self->{'iptables_obj'}->clear_ruleset_cache();
    }
    catch {
        $err = $_;
    };

    if ($err) {
        my $err_as_string = Cpanel::Exception::get_string($err);

        # This final removal will fail if any of the earlier removals failed, so it alone determines the success
        # or failure.
        $Whostmgr::TicketSupport::Whitelist::gl_logger->warn("Failed to remove cPanel support access iptables chain: $err_as_string!") unless $opts{'quiet'};
        return;
    }
    return 1;
}

=head2 $ipt->active

Returns a boolean value indicating whether the chain is both installed and active
(i.e. INPUT chain is passing its traffic through our chain)

=cut

sub active {
    my ($self) = @_;

    $self->{'iptables_obj'}->clear_ruleset_cache();
    my $have_chain = $self->{'iptables_obj'}->chain_exists();

    # Is the INPUT & OUTPUT chain set up to pass traffic through our chain?
    my $tables_ref = $self->{'iptables_obj'}->get_builtin_chains_that_reference_chain();

    return ( $have_chain && $tables_ref->{'INPUT'} && $tables_ref->{'OUTPUT'} );
}

=head2 $ipt->should_skip

Returns a boolean value indicating whether iptables should be skipped.

Skip iptables if CSF is installed and not disabled, because CSF takes over
control of iptables.

=cut

sub should_skip {
    return -e '/etc/csf' && !-e '/etc/csf/csf.disable';
}

1;
