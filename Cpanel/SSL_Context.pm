package Cpanel::SSL_Context;

# cpanel - Cpanel/SSL_Context.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::SSL_Context - Apply C<Cpanel::Server::TLSCache>

=head1 SYNOPSIS

    my $srv = IO::Socket::SSL->new(
        SSL_reuse_ctx => Cpanel::SSL_Context->new(),
        #...
    );

    while (my $to_client = $srv->accept()) {
        1 while $srv->check_tls_cache();

        #the usual fork(), etc.
    }

=head1 DISCUSSION

This subclass of C<IO::Socket::SSL::SSL_Context> implements the callbacks
necessary to deploy C<Cpanel::Server::TLSCache> with C<IO::Socket::SSL>.

=head1 TODO

Currently all of a server’s instances of C<Cpanel::SSL_Context> share
the same instance of C<Cpanel::Server::TLSCache>. This is not ideal.

=cut

use strict;
use warnings;

use IO::Socket::SSL ();
use Net::SSLeay     ();

use parent -norequire, qw( IO::Socket::SSL::SSL_Context );

use Cpanel::Hostname         ();
use Cpanel::NetSSLeay::SSL   ();
use Cpanel::Server::TLSCache ();

#TODO: Find a way to make this not be a singleton.
my $TLS_CACHE;

sub new {
    my ( $class, @key_values ) = @_;

    #Instantiate this right off the bat so that we
    #know that all processes that use this instance will have the cache.
    $TLS_CACHE ||= Cpanel::Server::TLSCache->new(@key_values);

    my $self = $class->SUPER::new(
        @key_values,

        #Trying to wrap this in a closure that captures $self
        #doesn’t seem to work. :-(
        SSL_create_ctx_callback => \&_SSL_create_ctx_callback,
    );

    return $self;
}

sub check_tls_cache {
    my ($self) = @_;

    return $TLS_CACHE->check();
}

sub _SSL_create_ctx_callback {
    my ($ctx_num) = @_;

    #TODO: Net::SSLeay allows storing an additional parameter
    #to pass to the callback here. It may be possible to use this to
    #solve the $TLS_CACHE singleton problem.
    Net::SSLeay::CTX_set_tlsext_servername_callback(
        $ctx_num,
        \&_CTX_set_tlsext_servername_callback,
    );

    return;
}

sub _CTX_set_tlsext_servername_callback {
    my ($ssl) = @_;

    $ssl = Cpanel::NetSSLeay::SSL->new_wrap($ssl);

    my $ctx;

    my $h = $ssl->get_servername();

    if ( length $h && $h ne Cpanel::Hostname::gethostname() ) {
        if ( $h =~ tr</\0><> ) {
            die "Invalid/unsafe domain: “$h”";
        }

        $ctx = $TLS_CACHE->get_ctx_for_domain($h);

        if ($ctx) {
            $ssl->set_CTX($ctx);
        }
    }

    return $ctx;
}

END {
    undef $TLS_CACHE;
}

1;
