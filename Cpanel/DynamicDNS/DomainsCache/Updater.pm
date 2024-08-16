package Cpanel::DynamicDNS::DomainsCache::Updater;

# cpanel - Cpanel/DynamicDNS/DomainsCache/Updater.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::DynamicDNS::DomainsCache::Updater

=head1 SYNOPSIS

    use Cpanel::WebCalls::Datastore::Write ();
    use Cpanel::DynamicDNS::DomainsCache::Updater ();

    Cpanel::WebCalls::Datastore::Write->new_p()->then( sub {

        # IMPORTANT: This all must happen under the authoritative
        # datastore’s exclusive lock!!

        my $cache_updater = Cpanel::DynamicDNS::DomainsCache::Updater->new();

        $cache_updater->update_if_needed(
            \@domains_to_remove,
            \@domains_to_add,
        );

        $cache_update->save_if_needed();
    } );

=head1 DESCRIPTION

This module implements the writer-side maintenance logic for the
dynamic DNS domains cache. It’s here as a way to avoid having to recreate
the entire cache every time a DDNS domain is created/deleted/renamed.

=head1 IMPORTANT!!

This module’s work B<MUST> happen under an exclusive lock of the
authoritative datastore!

=cut

#----------------------------------------------------------------------

use Cpanel::DynamicDNS::DomainsCache::Common ();

use Cpanel::Autodie  ();
use Cpanel::LoadFile ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new()

Starts the update. This will remove any existing cache file.

The dynamic DNS datastore B<MUST> be write-locked before this is called.

=cut

sub new ($class) {

    my $path = Cpanel::DynamicDNS::DomainsCache::Common::get_path();

    my $text = Cpanel::LoadFile::load_if_exists($path);

    Cpanel::Autodie::unlink_if_exists($path);

    my $self = bless {
        _text => $text,
    }, $class;

    return $self;
}

=head2 I<OBJ>->update_if_needed( \@REMOVE [, \%ADD] )

Removes and adds entries as specified. @REMOVE is an array of domains,
while %ADD is a hash of domain => ID.

Returns nothing.

=cut

sub update_if_needed ( $self, $remove_ar, $add_hr = undef ) {

    # If there was no cache in the first place, then there’s nothing
    # to bother updating.
    if ( defined $self->{'_text'} ) {

        if ($remove_ar) {
            $self->{'_text'} =~ s<\n\Q$_\E:.+?\n><\n> for @$remove_ar;
        }

        if ($add_hr) {
            $self->{'_text'} .= "$_:$add_hr->{$_}\n" for keys %$add_hr;
        }
    }

    return;
}

=head2 I<OBJ>->save_if_needed()

Writes out the changed datastore (if applicable). Returns nothing.

=cut

sub save_if_needed ($self) {

    # It’s possible that this will just write out the same list as before.
    if ( $self->{'_text'} ) {

        my $path = Cpanel::DynamicDNS::DomainsCache::Common::get_path();

        # We don’t need a lock on the cache in this case because
        # we already have a lock on the main datastore.
        local ( $@, $! );
        require Cpanel::FileUtils::Write;
        Cpanel::FileUtils::Write::write( $path, $self->{'_text'} );
    }

    return;
}

1;
