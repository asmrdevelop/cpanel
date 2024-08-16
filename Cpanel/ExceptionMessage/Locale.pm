package Cpanel::ExceptionMessage::Locale;

# cpanel - Cpanel/ExceptionMessage/Locale.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
#NOTE about $@ in this module:
#
#In many (i.e., almost all) cases, instances of this class will be a member of
#an object that $@ refers to. Thus, as a courtesy, this module prefixes calls
#to external code with "local $@", in case that external code alters $@. While
#it is arguable that only eval() should actually publish changes to $@, there
#simply is too much Perl code that behaves otherwise not to take this step.
#----------------------------------------------------------------------

use strict;
use warnings;

use parent qw(Cpanel::ExceptionMessage);

use Cpanel::ExceptionMessage::Raw ();

sub new {
    my ( $class, $str, @mktxt_opts ) = @_;

    #See NOTE above.
    local $@;

    my $self = eval {
        require Cpanel::Locale;
        {
            _raw_string => $str,
            _mktxt_opts => \@mktxt_opts,

            #NOTE: JSON::XS blows up if you instantiate a Cpanel::Locale object
            #during TO_JSON(). Create this here to work around that.
            _locale => Cpanel::Locale->get_handle(),
        };

    } or do {
        warn "Failed to instantiate $class; falling back to Raw: $@";

        return Cpanel::ExceptionMessage::Raw->new( Cpanel::ExceptionMessage::Raw::convert_localized_to_raw( $str, @mktxt_opts ) );
    };

    return bless $self, $class;
}

sub to_en_string {
    my ($self) = @_;

    my $locale = $self->{'_locale'};

    #See NOTE above.
    local $@;

    # If we're in global destruction, do the best we can.
    return Cpanel::ExceptionMessage::Raw::convert_localized_to_raw( $self->{'_raw_string'}, @{ $self->{'_mktxt_opts'} } ) unless $locale;

    #makethis_base() leaves the phrase/key alone
    #and uses English localization (plurals, numbers, etc.) semantics.
    return $locale->makethis_base( $self->{'_raw_string'}, @{ $self->{'_mktxt_opts'} } );    ## no extract maketext
}

sub to_locale_string {
    my ($self) = @_;

    my $locale = $self->{'_locale'};

    #See NOTE above.
    local $@;

    # If we're in global destruction, do the best we can.
    return Cpanel::ExceptionMessage::Raw::convert_localized_to_raw( $self->{'_raw_string'}, @{ $self->{'_mktxt_opts'} } ) unless $locale;

    #makevar() is the same as maketext(), but the phrase parser   ## no extract maketext
    #doesn't catch makevar().
    return $locale->makevar( $self->{'_raw_string'}, @{ $self->{'_mktxt_opts'} } );    ## no extract maketext (for _maketext_opts, are we sure the value of _raw_string is marked?)
}

#The generic to_string() method prints all unique strings,
#including the raw string if there were no maketext() arguments.   ## no extract maketext
sub to_string {
    my ($self) = @_;

    my @strings = ( $self->to_locale_string(), $self->to_en_string() );

    my %seen;
    return join( $/, grep { !$seen{$_}++ } @strings );
}

sub get_language_tag {
    return $_[0]->{'_locale'}->get_language_tag();
}

1;
