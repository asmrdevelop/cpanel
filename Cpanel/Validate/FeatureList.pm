package Cpanel::Validate::FeatureList;

# cpanel - Cpanel/Validate/FeatureList.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Try::Tiny;

use Cpanel::Context ();
use Cpanel::Locale  ();

use Cpanel::Validate::FilesystemNodeName ();

my $locale;

sub is_valid_feature_list_name {
    my ($name) = @_;

    Cpanel::Context::must_be_list();

    if ( !length $name ) {
        return ( 0, _get_locale()->maketext('Feature list names may not be empty or undefined.') );
    }
    if ( $name !~ /\A[a-zA-Z0-9: ?\[\],\@!\(\)+\.{}\$;%=_~-]+\z/m ) {
        return ( 0, _get_locale()->maketext( 'Feature list names may only contain the following characters: [join, ,_1]', [ qw( a-z A-Z 0-9 _ - + ? [ ] ( ) { } = ! . : ; ~ @ $ % ), ',', _get_locale()->maketext('(space)') ] ) );
    }

    my $err;
    try {
        Cpanel::Validate::FilesystemNodeName::validate_or_die($name);
    }
    catch {
        $err = $_->to_string();
    };

    return $err ? ( 0, $err ) : 1;
}

sub _get_locale {
    return $locale ||= Cpanel::Locale->get_handle();
}

1;
