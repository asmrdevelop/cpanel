package Cpanel::Template::Plugin::CPHash;

# cpanel - Cpanel/Template/Plugin/CPHash.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use base 'Template::Plugin';
use Template::VMethods;

sub load {
    my ( $class, $context ) = @_;

    $context->define_vmethod(
        'hash',
        'reverse',
        sub {
            my $hash_r = shift();

            #reversing the hash as a list value flips the keys/values
            return { reverse %{$hash_r} };
        }
    );

    return $class;
}

sub vmethod {
    my ( undef, $vmethod, $hash_r, @args ) = @_;
    return $Template::VMethods::HASH_VMETHODS->{$vmethod}->( $hash_r, @args );
}

1;
