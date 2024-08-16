package Cpanel::DynamicDNS::DomainsCache;

# cpanel - Cpanel/DynamicDNS/DomainsCache.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::DynamicDNS::DomainsCache

=head1 SYNOPSIS

    use Cpanel::DynamicDNS::DomainsCache ();

    my $domains_ar = Cpanel::PromiseUtils::wait_anyevent(
        Cpanel::DynamicDNS::DomainsCache::read_p( timeout => 30 ),
    )->get();

=head1 DESCRIPTION

This module interfaces around a cache of the system’s dynamic DNS domains.

It exposes both read and write controls (rather than having separate
read/write modules) because any access to the dynamic DNS datastore requires
root, and it’s understood that a reader of the main datastore may write this
one.

This module assumes use of L<AnyEvent>.

=head1 ENSURING CACHE INTEGRITY

For this cache to work correctly we have to avoid any window where the
cache contents mismatch the datastore. Becaue we can’t update this cache
atomically with the datastore, we need a different approach.

The way this works is:

=over

=item * Anything that changes the datastore will first delete the cache,
then change the datastore, then install the updated cache. This all happens
under an exclusive lock on the datastore. Thus, the only two states are:
cache & datastore in sync, or cache is missing.

See L<Cpanel::DynamicDNS::DomainsCache::Updater> for an implementation
of this logic.

=item * Reads of the cache happen under a shared lock on the datastore.
Thus there will be no conflict with a process that updates the datastore.

=item * If the cache is missing, a reader recreates it under the same
shared lock. The lock prevents datastore changes during this time.

=back

=cut

#----------------------------------------------------------------------

use Cpanel::LoadFile ();

use Cpanel::WebCalls::Datastore::Read        ();
use Cpanel::DynamicDNS::DomainsCache::Common ();

# for testing
our $_BEFORE_SAVE_CR;

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 promise(%domain_id) = read_p(%OPTS)

Returns a promise whose resolution is a hashref of the system’s DDNS
domains to their entry IDs.

=cut

sub read_p (%opts) {
    my $p = Cpanel::WebCalls::Datastore::Read->lock_p( %opts{'timeout'} );

    return $p->then(
        sub {
            _read_cache() || do {
                my $ret;

                my $xaction = _get_xaction();

                # We want to prevent multiple reader processes from
                # recreating the cache concurrently. To do that, we lock
                # the cache, then check to see if its contents now exist.
                # If that happens, then something installed a cache while we
                # were waiting for the lock. Since we know that any installed
                # cache is a valid one, we no longer need to write the cache,
                # and we can proceed by just parsing the cache’s new data.
                #
                if ( length ${ $xaction->get_data() } ) {
                    $xaction->close_or_die();
                    $ret = _parse_cache( $xaction->get_data() );
                }
                else {

                    my %domain_id;

                    Cpanel::WebCalls::Datastore::Read->for_each_of_type(
                        'DynamicDNS',
                        sub ( $id, $entry, @ ) {
                            $domain_id{ $entry->domain() } = $id;
                        }
                    );

                    # A way for testing code to prolong the transaction
                    # to better test that the datastore is only written once.
                    $_BEFORE_SAVE_CR->() if $_BEFORE_SAVE_CR;

                    _try_to_save_cache( $xaction, \%domain_id );

                    $ret = \%domain_id;
                }

                $ret;
            };
        }
    );
}

#----------------------------------------------------------------------

*_PATH = *Cpanel::DynamicDNS::DomainsCache::Common::get_path;

sub _read_cache () {
    my $content = Cpanel::LoadFile::load_if_exists( _PATH() );

    return $content && _parse_cache( \$content );
}

sub _parse_cache ($content_sr) {
    my @domains = split m<\n>, $$content_sr;
    shift @domains;

    return { map { split m<:> } @domains };
}

sub _try_to_save_cache ( $xaction, $data_ref ) {

    # The leading newline avoids writing an empty file.
    # Thus we can more easily distinguish between a nonexistent cache
    # versus an empty one.
    my $str_sr = Cpanel::DynamicDNS::DomainsCache::Common::serialize($data_ref);

    $xaction->set_data($str_sr);
    _save_xaction($xaction);

    return;
}

sub _get_xaction () {
    local ( $@, $! );
    require Cpanel::Transaction::File::Raw;
    return Cpanel::Transaction::File::Raw->new( path => _PATH() );
}

sub _save_xaction ($xaction) {
    local $@;
    warn if !eval { $xaction->save_and_close_or_die() };

    return;
}

1;
