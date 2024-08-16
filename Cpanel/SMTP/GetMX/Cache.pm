package Cpanel::SMTP::GetMX::Cache;

# cpanel - Cpanel/SMTP/GetMX/Cache.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Mkdir    ();
use Cpanel::Autowarn ();

use parent qw(Cpanel::CacheFile);

=encoding utf-8

=head1 NAME

Cpanel::SMTP::GetMX::Cache - Cache results from Cpanel::SMTP::GetMX

=head1 SYNOPSIS

    use Cpanel::SMTP::GetMX::Cache;

    Cpanel::SMTP::GetMX::Cache::delete_cache_for_domains( \@domains );

    Cpanel::SMTP::GetMX::Cache->save( $records_hr, $domain );

    Cpanel::SMTP::GetMX::Cache->load($domain)

=cut

use constant {
    _TTL  => 86400 * 32,    # 32 days
    _MODE => 0644,          #world-readable (dns is public).
};

#overridden in tests
our $_BASE_DIR = '/var/cpanel/getmx/cache';

my $_did_init_path = 0;

sub _init_path {
    Cpanel::Mkdir::ensure_directory_existence_and_mode( $_BASE_DIR, 0755 );
    $_did_init_path = 1;
    return;
}

sub _PATH {
    my ( $self, $host ) = @_;
    $self->_init_path() if !$_did_init_path && $> == 0;
    return "$_BASE_DIR/$host";
}

sub _LOAD_FROM_FH {
    my ( $self, $fh ) = @_;

    # An empty result is an acceptable cache
    # item, which also allows us to avoid the read/parse
    return undef if !-s $fh;
    return $self->SUPER::_LOAD_FROM_FH($fh);
}

sub _DUMP {
    my ( $self, $ref ) = @_;

    # We write an empty file if there are no results
    # since we only want to do another lookup
    # when the cache expires
    return '' if !$ref;
    return $self->SUPER::_DUMP($ref);
}

=head2 delete_cache_for_domains($domains_ar)

Remove an arrayref of domains from the cache.

=cut

sub delete_cache_for_domains {
    my ($domains_ar) = @_;
    Cpanel::Autowarn::unlink("$_BASE_DIR/$_") for @$domains_ar;
    return 1;
}

1;
