package Cpanel::CPAN::Locales::Legacy;

use strict;

# This module is dynamiclly loaded by
# Cpanel::CPAN::Locales
# is called.  This allows us to use Cpanel::CPAN::Locales without
# the overhead of this module.

# We currently do not use this function since
# Cpanel::CPAN::Locale::Maketext::Utils::numf has been
# modified to wrap get_formatted_decimal
sub numf {
    my ( $self, $always_return ) = @_;
    my $class = ref($self) ? ref($self) : $self;
    $always_return ||= 0;
    $self->{'language_data'}{'misc_info'}{'cldr_formats'}{'_decimal_format_group'}   = '' if !defined $self->{'language_data'}{'misc_info'}{'cldr_formats'}{'_decimal_format_group'};
    $self->{'language_data'}{'misc_info'}{'cldr_formats'}{'_decimal_format_decimal'} = '' if !defined $self->{'language_data'}{'misc_info'}{'cldr_formats'}{'_decimal_format_decimal'};

    if ( !$self->{'language_data'}{'misc_info'}{'cldr_formats'}{'_decimal_format_group'} || !$self->{'language_data'}{'misc_info'}{'cldr_formats'}{'_decimal_format_decimal'} ) {
        if ($always_return) {
            if ( $self->{'language_data'}{'misc_info'}{'cldr_formats'}{'_decimal_format_group'} || !$self->{'language_data'}{'misc_info'}{'cldr_formats'}{'_decimal_format_decimal'} ) {
                return 2 if $self->{'language_data'}{'misc_info'}{'cldr_formats'}{'_decimal_format_group'} eq '.';
                return 1;
            }
            elsif ( !$self->{'language_data'}{'misc_info'}{'cldr_formats'}{'_decimal_format_group'} || $self->{'language_data'}{'misc_info'}{'cldr_formats'}{'_decimal_format_decimal'} ) {
                return 2 if $self->{'language_data'}{'misc_info'}{'cldr_formats'}{'_decimal_format_decimal'} eq ',';
                return 1;
            }
            else {
                return 1;
            }
        }
    }

    if ( $self->{'language_data'}{'misc_info'}{'cldr_formats'}{'decimal'} eq "\#\,\#\#0\.\#\#\#" ) {
        if ( $self->{'language_data'}{'misc_info'}{'cldr_formats'}{'_decimal_format_group'} eq ',' && $self->{'language_data'}{'misc_info'}{'cldr_formats'}{'_decimal_format_decimal'} eq '.' ) {
            return 1;
        }
        elsif ( $self->{'language_data'}{'misc_info'}{'cldr_formats'}{'_decimal_format_group'} eq '.' && $self->{'language_data'}{'misc_info'}{'cldr_formats'}{'_decimal_format_decimal'} eq ',' ) {
            return 2;
        }
    }
    elsif ( $always_return && $self->{'language_data'}{'misc_info'}{'cldr_formats'}{'_decimal_format_group'} && $self->{'language_data'}{'misc_info'}{'cldr_formats'}{'_decimal_format_decimal'} ) {
        return 2 if $self->{'language_data'}{'misc_info'}{'cldr_formats'}{'_decimal_format_decimal'} eq ',';
        return 2 if $self->{'language_data'}{'misc_info'}{'cldr_formats'}{'_decimal_format_group'} eq '.';
        return 1;
    }

    return [
        $self->{'language_data'}{'misc_info'}{'cldr_formats'}{'decimal'},
        $self->{'language_data'}{'misc_info'}{'cldr_formats'}{'_decimal_format_group'},
        $self->{'language_data'}{'misc_info'}{'cldr_formats'}{'_decimal_format_decimal'},
    ];
}

1;
