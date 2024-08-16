package Cpanel::Exception::Collection;

# cpanel - Cpanel/Exception/Collection.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception );

use Cpanel::LocaleString ();

my $EXCEPTION_SEPARATOR = "\n";

sub _LINE_HEADER {
    my ($num) = @_;

    return Cpanel::LocaleString->new( 'Error #[numf,_1]:', $num );
}

#Parameters:
#   exceptions  (arrayref) The list of exceptions to return.
#
sub _default_phrase {
    my ($self) = @_;

    my $excs_ar = $self->get('exceptions') or do {
        die ref($self) . ' instances must have “exceptions”!';
    };

    if ( !@$excs_ar ) {
        die "Must have at least 1 exception (or why do you need a “collection”?)";
    }

    return Cpanel::LocaleString->new(
        '[quant,_1,error,errors] occurred:',
        scalar @$excs_ar,
    );
}

sub to_en_string {
    my ($self) = @_;

    return $self->_stringify_specific('to_en_string');
}

sub to_en_string_no_id {
    my ($self) = @_;

    return $self->_stringify_specific('to_en_string_no_id');
}

sub to_locale_string {
    my ($self) = @_;

    return $self->_stringify_specific('to_locale_string');
}

sub to_locale_string_no_id {
    my ($self) = @_;

    return $self->_stringify_specific('to_locale_string_no_id');
}

my %LINE_HEADER_TRANSLATOR = qw(
  to_en_string              makethis_base
  to_locale_string          makevar
  to_en_string_no_id        makethis_base
  to_locale_string_no_id    makevar
);

sub _stringify_specific {
    my ( $self, $method ) = @_;

    my $exceptions_ar = $self->get('exceptions');

    my @lines = map { UNIVERSAL::isa( $_, 'Cpanel::Exception' ) ? $_->$method() : $_ } @$exceptions_ar;

    my $translator_name = $LINE_HEADER_TRANSLATOR{$method} or do {
        die "Invalid method: $method";
    };

    #NOTE: This serves the same purpose as it does in
    #Cpanel::ExceptionMessage::Locale: we need to prevent
    #Cpanel::CPAN::Locale::Maketext::Utils from clobbering $@.
    local $@;

    #Prefix the separator + header onto each line.
    for my $l ( 0 .. $#lines ) {
        my $this_header = _locale()->$translator_name( _LINE_HEADER( 1 + $l )->to_list() );
        substr( $lines[$l], 0, 0, $EXCEPTION_SEPARATOR . "$this_header " );
    }

    return $self->can("SUPER::$method")->($self) . join q<>, @lines;
}

my $locale;

sub _locale {
    require Cpanel::Locale;
    return $locale ||= Cpanel::Locale->get_handle();
}

1;
