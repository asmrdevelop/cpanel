package Cpanel::SSL::CABundleCache;

# cpanel - Cpanel/SSL/CABundleCache.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::SSL::CABundleCache - cache a CA Bundle based on URL

=head1 SYNOPSIS

    my $cert_obj = Cpanel::SSL::Objects::Certificate->new( cert => $cert_pem );
    my $url = $cert_obj->caIssuers_url();

    my $cab = Cpanel::SSL::CABundleCache->load($url);

=head1 DISCUSSION

A cache on top of L<Cpanel::SSL::CAIssuers>. The cache is world-readable, but
only root can write to it; if the cache doesn’t have an entry for a given URL,
this calls a cPanel-distributed admin call to fetch the CA bundle and populate
the cache.

=cut

use strict;
use warnings;

use parent qw( Cpanel::CacheFile );

use Cpanel::Exception  ();
use Cpanel::Hash       ();
use Cpanel::LoadModule ();
use Cpanel::PwCache    ();

use constant _TTL => 604800;    #7 days

use constant _MODE => 0644;

use constant _OWNER => ( ('cpanelcabcache') x 2 );

#overridden in tests
sub _dir {
    my $homedir = Cpanel::PwCache::gethomedir('cpanelcabcache');
    return "$homedir/cache";
}

sub _PATH {
    my ( $class, $url ) = @_;

    return sprintf( "%s/%s", _dir(), _url_to_key($url) );
}

sub _url_to_key {
    my ($url) = @_;

    if ( !length $url ) {
        die Cpanel::Exception::create_raw( 'Empty', 'A URL is required!' );
    }

    my $hash = sprintf '%x', Cpanel::Hash::fnv1a_32($url);

    #It’s pretty unlikely that a CA would include a super-long
    #caIssuers URL in a certificate, but just in case.
    #
    #Note that we computed the $hash BEFORE this truncation;
    #that way if two long URLs are identical except for their trailing bytes,
    #the lookup integrity is still intact.
    $url = substr( $url, 0, 220 );

    #Again, it’s important that we computed $hash BEFORE we replace
    #the filesystem-unsafe characters.
    $url =~ tr</.><__>;

    return "$url.$hash";
}

#If we call this as either root or cpanelcabcache, then save;
#otherwise, this is a no-op.
sub save {
    my ( $class, @args ) = @_;

    my $privs = $> || do {
        Cpanel::LoadModule::load_perl_module('Cpanel::AccessIds::ReducedPrivileges');
        Cpanel::AccessIds::ReducedPrivileges->new('cpanelcabcache');
    };

    #Don’t bother trying if we’re not root.
    if ( Cpanel::PwCache::getusername() eq 'cpanelcabcache' ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::Mkdir');

        'Cpanel::Mkdir'->can('ensure_directory_existence_and_mode')->(
            _dir(),
            0711,
        );

        return $class->SUPER::save(@args);
    }

    return;
}

sub _admin_cabundle_fetch {
    my ($url) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::AdminBin::Call');
    return Cpanel::AdminBin::Call::call( 'Cpanel', 'ssl_call', 'GET_CACHED_CABUNDLE_URL', $url );
}

#overridden in tests
sub _get_cabundle_pem {
    my ( $class, $url ) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::SSL::CAIssuers');

    return Cpanel::SSL::CAIssuers::get_cabundle_pem($url) || q<>;
}

sub _LOAD_FRESH {
    my ( $class, $url ) = @_;

    #We’re paranoid about our X.509 certificate parsing.
    #(It’s pure Perl, so it *should* be fine … but hey.)
    #So, we never actually parse as root; if we’re called here as root,
    #then let’s fork()/setuid() so we parse unprivileged.
    if ( !$< ) {

        #ForkSync.pm includes a die() that will print to STDERR.
        #We blackhole that for the sake of admin binaries and such
        #that may read STDERR and STDOUT as the same thing.
        local *STDERR;
        open \*STDERR, '>', '/dev/null' or die "Can’t blackhole STDERR: $!";

        Cpanel::LoadModule::load_perl_module('Cpanel::AccessIds');
        return Cpanel::AccessIds::do_as_user_with_exception(
            ( $class->_OWNER() )[0],
            sub { return $class->_get_cabundle_pem($url) },
        );
    }

    #We want regular users to call the admin layer, which will
    #populate this cache entry for the next user.
    if ( Cpanel::PwCache::getusername() ne 'cpanelcabcache' ) {
        return _admin_cabundle_fetch($url);
    }

    #We only get here as cpanelcabcache.
    return $class->_get_cabundle_pem($url);
}

1;
