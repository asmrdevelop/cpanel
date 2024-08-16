package Cpanel::CLDR::DateTime;

# cpanel - Cpanel/CLDR/DateTime.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Context    ();
use Cpanel::LoadModule ();

sub day_stand_alone_abbreviated {
    my $loc_tag = shift;
    return _get_from_dt_locale( 'day_stand_alone_abbreviated', $loc_tag );
}

sub day_stand_alone_wide {
    my $loc_tag = shift;
    return _get_from_dt_locale( 'day_stand_alone_wide', $loc_tag );
}

sub month_stand_alone_abbreviated {
    my $loc_tag = shift;
    return _get_from_dt_locale( 'month_stand_alone_abbreviated', $loc_tag );
}

sub month_stand_alone_wide {
    my $loc_tag = shift;
    return _get_from_dt_locale( 'month_stand_alone_wide', $loc_tag );
}

sub _get_from_dt_locale {
    my ( $to_get, $locale_tag ) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::Locale');

    $locale_tag ||= do {

        #NOTE: We shouldn’t need to load Locale just to determine which
        #locale is actually used by default. We could refactor that logic,
        #but whatever uses this module probably already has Locale.
        #The load_perl_module() is just a safety net.
        Cpanel::Locale->get_handle()->get_language_tag();
    };

    Cpanel::LoadModule::load_perl_module('DateTime::Locale');

    my $dt_loc;
    for my $loc ( $locale_tag, Cpanel::Locale->get_handle->fallback_languages ) {
        $dt_loc = eval { DateTime::Locale->load($loc); } and last;
    }

    my $thing = $dt_loc->$to_get();

    #Duplicate array refs to ensure that a template
    #can’t corrupt module internals.
    #(NB: As of 0.46, DateTime::Locale does NOT do this for us!)

    #XXX: DateTime::Locale does “use utf8” when parsing the module,
    #which can make for funkiness when this data goes out into the world.
    #String::UnicodeUTF8::get_utf8() changes those into byte strings,
    #which our stuff handles much better.
    Cpanel::LoadModule::load_perl_module('String::UnicodeUTF8');

    if ( 'ARRAY' eq ref $thing ) {
        Cpanel::Context::must_be_list();

        return map { String::UnicodeUTF8::get_utf8($_) } @$thing;
    }

    return String::UnicodeUTF8::get_utf8($thing) if !ref $thing;

    die "$to_get is a $thing; I don’t know what to do with that!";
}

1;
