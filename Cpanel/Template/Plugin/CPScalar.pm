package Cpanel::Template::Plugin::CPScalar;

# cpanel - Cpanel/Template/Plugin/CPScalar.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use base 'Template::Plugin';

use Cpanel::StringFunc::Trim ();

sub load {
    my ( $class, $context ) = @_;

    $context->define_vmethod(
        'scalar',
        'sprintf',
        sub {
            return sprintf( $_[1], $_[0] );
        }
    );

    $context->define_vmethod( 'scalar', 'lc', sub { lc shift() } );

    $context->define_vmethod( 'scalar', 'substr', \&_substr );

    $context->define_vmethod( 'scalar', 'uc', sub { uc shift() } );

    $context->define_vmethod( 'scalar', 'ws_trim', \&Cpanel::StringFunc::Trim::ws_trim );

    $context->define_vmethod( 'scalar', 'textbreak', \&textbreak );

    $context->define_vmethod( 'scalar', 'breakOn', \&breakOn );

    $context->define_vmethod( 'scalar', 'quotemeta', sub { quotemeta shift() } );

    return $class;
}

#substr is really picky about its args...
my $_substr_funcs = {
    2 => sub { CORE::substr( $_[0], $_[1] ) },
    3 => sub { CORE::substr( $_[0], $_[1], $_[2] ) },
    4 => sub { CORE::substr( $_[0], $_[1], $_[2], $_[3] ) },
};

sub _substr {
    return $_substr_funcs->{ scalar @_ }->(@_);
}

sub quotemeta { return quotemeta( $_[1] ); }                            #doesn't override built-in
sub sprintf   { return sprintf( $_[1], $_[2] ) }                        #doesn't override built-in
sub lc        { return lc $_[1]; }                                      #doesn't override built-in
sub uc        { return uc $_[1]; }                                      #doesn't override built-in
sub ws_trim   { return &Cpanel::StringFunc::Trim::ws_trim( $_[1] ); }

sub textbreak {
    my $text             = shift;
    my $max_column_width = shift || 80;
    my $splitwith        = shift || ' ';
    my $new_text         = '';

    my $offset = 0;
    while ( length($text) > $offset ) {
        my $part = substr( $text, $offset, $max_column_width );
        $new_text .= $new_text ? $splitwith . $part : $part;
        $offset += length $part;
    }

    return $new_text;
}

sub breakOn {
    my ( $text, $regex ) = @_;

    $text =~ s/($regex)/$1<wbr><a class='wbr'><\/a>/g;

    return $text;
}

1;
