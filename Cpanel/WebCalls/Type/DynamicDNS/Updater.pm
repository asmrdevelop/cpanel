package Cpanel::WebCalls::Type::DynamicDNS::Updater;

# cpanel - Cpanel/WebCalls/Type/DynamicDNS/Updater.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::WebCalls::Type::DynamicDNS::Updater

=head1 DESCRIPTION

This module implements L<Cpanel::WebCalls::UpdaterBase> for
dynamic DNS.

Specifically, it updates the dynamic DNS domains cache.
(cf. L<Cpanel::DynamicDNS::DomainsCache>)

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::WebCalls::UpdaterBase';

use Cpanel::DynamicDNS::DomainsCache::Updater ();

#----------------------------------------------------------------------

sub _INIT ($self) {
    $self->{'ddns_updater'} = Cpanel::DynamicDNS::DomainsCache::Updater->new();

    return;
}

sub _REMOVE ( $self, $id_entries_ar ) {
    my @id_entries = @$id_entries_ar;

    my @domains;

    while ( my ( undef, $entry ) = splice @id_entries, 0, 2 ) {
        push @domains, $entry->domain();
    }

    $self->{'ddns_updater'}->update_if_needed( \@domains );

    return;
}

sub _ADD ( $self, $id_entries_ar ) {
    my %id_entry = @$id_entries_ar;

    $_ = $_->domain() for values %id_entry;

    $self->{'ddns_updater'}->update_if_needed( undef, { reverse %id_entry } );

    return;
}

sub _UPDATE ( $self, $old_id, $old_entry, $new_id, $new_entry ) {    ## no critic qw(ManyArgs) - mis-parse
    $self->{'ddns_updater'}->update_if_needed(
        [ $old_entry->domain() ],
        { $new_entry->domain() => $new_id },
    );

    return;
}

sub _FINISH ($self) {
    $self->{'ddns_updater'}->save_if_needed();

    return;
}

1;
