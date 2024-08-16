package Cpanel::Template::Plugin::JSON;

# cpanel - Cpanel/Template/Plugin/JSON.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use base 'Template::Plugin';

use Cpanel::JSON          ();
use Cpanel::Encoder::JSON ();

BEGIN {
    *_parse     = \&Cpanel::JSON::Load;
    *_stringify = \&Cpanel::JSON::Dump;
}

sub load {
    my ( $class, $context ) = @_;

    $context->define_vmethod( 'scalar', 'json', \&Cpanel::Encoder::JSON::json_encode_str );
    $context->define_vmethod( 'hash',   'json', \&_safe_dump );
    $context->define_vmethod( 'list',   'json', \&_safe_dump );

    return $class;
}

# required for unit test
sub canonical {

    # Note: this makes the object canonical forever
    # in order to preserve legacy behavior :(
    #
    # See unit tests t/Cpanel-Template-Plugin-Whostmgr_breadcrumb*.t
    no warnings 'redefine';
    *_stringify = \&Cpanel::JSON::canonical_dump;
    return;
}

sub parse {
    shift;
    goto &_parse;
}

sub loadfile {
    shift;
    goto &Cpanel::JSON::LoadFile;
}

sub stringify {
    shift;
    my $raw_json = _stringify(@_);
    $raw_json =~ s{<}{\\u003C}g if $raw_json =~ tr{<}{};
    return $raw_json;
}

sub _safe_dump {
    return stringify( undef, @_ );
}

1;
