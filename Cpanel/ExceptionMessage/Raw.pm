package Cpanel::ExceptionMessage::Raw;

# cpanel - Cpanel/ExceptionMessage/Raw.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------

use strict;
use warnings;

#Needs to work in 5.8, so no parent.pm.
use base qw(Cpanel::ExceptionMessage);

use Cpanel::Locale::Utils::Fallback ();

sub new {
    my ( $class, $str ) = @_;

    my $str_copy = $str;

    return bless( \$str_copy, $class );
}

sub to_string {
    my ($self) = @_;

    return $$self;
}

sub get_language_tag {
    return 'en';
}

BEGIN {
    *Cpanel::ExceptionMessage::Raw::convert_localized_to_raw = *Cpanel::Locale::Utils::Fallback::interpolate_variables;
    *Cpanel::ExceptionMessage::Raw::to_locale_string         = *Cpanel::ExceptionMessage::Raw::to_string;
    *Cpanel::ExceptionMessage::Raw::to_en_string             = *Cpanel::ExceptionMessage::Raw::to_string;
}
1;
