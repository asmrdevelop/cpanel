package Cpanel::Template::Plugin::VarCache;

# cpanel - Cpanel/Template/Plugin/VarCache.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use base 'Template::Plugin';

# This plugins allows for the following template toolkit usage
#
# [% VarCache.set('somekey', somehash) %]
#
# [% varcache.somekey.childkey1 %]
# [% varcache.somekey.childkey2 %]
# [% varcache.somekey.childkey3 %]
# [% varcache.somekey.user %]
# [% varcache.somekey.domain %]
#
# Because varcache is a namespace in Cpanel::Template
# the ident function will be called to generate the code
# for the varcache directive which allows us to use
# the hash lookup and avoid the overhead of Template::Stash::XS
#
# For additional details on the usage of this module please see
# https://cpanel.wiki/pages/viewpage.action?pageId=50664860
#
#
sub new {
    my ($class) = @_;
    return cVC->new($class);
}

package cVC;

#
# VarCacheObj is namespace in order to implement ident we have to use
# a singleton here.
#

our %S;

sub new {
    my ($class) = @_;
    return bless {}, $class;
}

sub clear {
    %S = ();
    return;
}

sub set {
    $S{ $_[1] } = $_[2];
    return '';    # Must return an empty string as it will get printed in the template
}

# See Cpanel::Template's declaration of
# the varcache namespace
sub ident {
    my ( $self, $lookup ) = @_;

    if ( $lookup->[2] eq q{'set'} ) {
        my $lr = $lookup->[3];
        $lr =~ s/^\[\s+//;
        $lr =~ s/\s+\]$//;
        my ( $lval, $rval ) = split( m{, }, $lr, 2 );
        return q{'';} . '$' . __PACKAGE__ . '::S{' . $lval . '} = ' . $rval;
    }

    # Template toolkit supports .html() and .uri() so we must as well
    # Added .json() since its a common scenario as well.
    #
    my $wrapper_code_start = '';
    my $wrapper_code_end   = '';
    if ( $lookup->[-2] eq q{'html'} ) {
        splice( @$lookup, -2, 2 );
        $wrapper_code_start = 'Cpanel::Encoder::Tiny::safe_html_encode_str(';
        $wrapper_code_end   = ')';
    }
    elsif ( $lookup->[-2] eq q{'uri'} ) {
        splice( @$lookup, -2, 2 );
        $wrapper_code_start = 'Cpanel::Encoder::URI::uri_encode_str(';
        $wrapper_code_end   = ')';
    }
    elsif ( $lookup->[-2] eq q{'json'} ) {
        splice( @$lookup, -2, 2 );
        $wrapper_code_start = 'Cpanel::JSON::SafeDump(';
        $wrapper_code_end   = ')';
    }

    my $stash_lookup_depth = int( scalar @{$lookup} / 2 ) - 1;

    # A lookup is in the form of
    # [
    #      '\'varcache\'',
    #      0,
    #      '\'this_app_group\'',
    #      0,
    #      '\'group\'',
    #      0
    # ];

    # We return the above as a hash lookup
    # which get injected into the compiled template
    return $wrapper_code_start . '$' . __PACKAGE__ . '::S'                                      #
      .                                                                                         #
      join( '->', map { "{" . ( $lookup->[ $_ * 2 ] ) . "}" } ( 1 .. $stash_lookup_depth ) )    #
      .                                                                                         #
      $wrapper_code_end;                                                                        #
}

package Cpanel::VarCacheObj;

use parent -norequire, 'cVC';

*STASH = \%cVC::S;

1;
