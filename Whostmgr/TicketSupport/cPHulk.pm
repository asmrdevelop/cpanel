
# cpanel - Whostmgr/TicketSupport/cPHulk.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::TicketSupport::cPHulk;

use strict;

use base 'Whostmgr::TicketSupport::Whitelist';

use Cpanel::Hulk::Admin ();

=head1 NAME

Whostmgr::TicketSupport::cPHulk

=head1 METHODS

=head2 $wl_obj->STATUS_NAME

The name of the status to return via the API call.

=cut

sub STATUS_NAME { return "hulk_wl_status"; }

sub new {
    my ( $package, @args ) = @_;
    my $self = $package->SUPER::new(@args);

    require Cpanel::Hulk::Admin::DB;
    $self->{'dbh'} = Cpanel::Hulk::Admin::DB::get_dbh();

    return $self;
}

=head2 $wl_obj->active

Returns a boolean value indicating whether the cPanel support IPs are whitelisted in cPHulk.

This check is done based on our saved hulk_wl_annotation, not based on whether the necessary IPs
appear in the whitelist, because we need to account for the possibiliy that the IPs were already
present in the whitelist without our intervention.

=cut

sub active {
    my ($self) = @_;
    my $hulk_wl_annotation = $self->_get_hulk_wl_annotation();
    return $hulk_wl_annotation->{'active'};
}

=head2 $wl_obj->setup

Adds the cPanel support IPs to the cPHulk whitelist.

=cut

sub setup {
    my ($self) = @_;

    $Whostmgr::TicketSupport::Whitelist::gl_logger->info("Setting up cPanel support access cPHulk whitelist rules");

    my $hulk_wl_annotation = $self->_get_hulk_wl_annotation();

    my $ok = 1;

    for my $access_ip ( @{ $self->{'access_ips'} } ) {
        my $ip    = $access_ip->{'ip'};
        my @hosts = @{ Cpanel::Hulk::Admin::get_sane_hosts( $self->{'dbh'}, 'white' ) || [] };
        if ( grep { $_ eq $ip } @hosts ) {
            $hulk_wl_annotation->{'already_whitelisted'}{$ip} = 1;
            $Whostmgr::TicketSupport::Whitelist::gl_logger->info("IP $ip was already whitelisted for cPHulk");
        }
        else {
            $ok &= !!Cpanel::Hulk::Admin::add_ip_to_list( $self->{'dbh'}, $ip, 'white' );
        }
    }

    if ($ok) {
        $hulk_wl_annotation->{'active'} = 1;
        $self->_set_hulk_wl_annotation($hulk_wl_annotation);
    }

    return $ok;
}

=head2 $wl_obj->unsetup

Removes the cPanel support IPs from the cPHulk whitelist.

=cut

sub unsetup {
    my ( $self, %opts ) = @_;

    $Whostmgr::TicketSupport::Whitelist::gl_logger->info("Removing cPanel support access cPHulk whitelist rules")
      unless $opts{'quiet'};

    my $hulk_wl_annotation = $self->_get_hulk_wl_annotation();

    my $ok = 1;

    for my $ip ( map { $_->{'ip'} } @{ $self->{'access_ips'} } ) {
        if ( $hulk_wl_annotation->{'already_whitelisted'}{$ip} ) {
            $Whostmgr::TicketSupport::Whitelist::gl_logger->info("Retaining cPHulk whitelist entry for $ip because it already existed on the system.")
              unless $opts{'quiet'};
        }
        else {
            $ok &= !!Cpanel::Hulk::Admin::remove_ip_from_list( $self->{'dbh'}, $ip, 'white' );
        }
    }

    if ($ok) {
        delete $hulk_wl_annotation->{'active'};
        delete $hulk_wl_annotation->{'already_whitelisted'};
        $self->_set_hulk_wl_annotation($hulk_wl_annotation);
    }

    return $ok;
}

=head2 $wl_obj->_get_hulk_wl_annotation

Returns the stored annotation / metadata (if any) about the cPHulk whitelist entries. Specifically,
  1. Whether we are considering the whitelist active or inactive. This is needed in order
     to assess whether any existing whitelist entries for the same IP addresses we're concerned
     with were added by us or were there to begin with.
  2. A saved list of any whitelist entries for the same IP addresses we're concerned with that
     were already in place before we started adding entries.

This added hulk_wl_annotation is necessary for the cPHulk whitelist because our own entries are just
being lumped in along with any existing ones, whereas for iptables we have a separate named
chain that can easily distinguish our rules from existing rules.

=cut

sub _get_hulk_wl_annotation {
    my ($self) = @_;
    return $self->{'store'}->get('hulk_wl_annotation');
}

=head2 $wl_obj->_set_hulk_wl_annotation($hulk_wl_annotation)

Saves the cPHulk whitelist hulk_wl_annotation back to the data store.

The argument should be the same type of structure returned by _get_hulk_wl_annotation.

=cut

sub _set_hulk_wl_annotation {
    my ( $self, $hulk_wl_annotation ) = @_;
    return $self->{'store'}->set( 'hulk_wl_annotation', $hulk_wl_annotation ) ? $self : undef;
}

1;
