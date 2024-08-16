package Cpanel::SetEnvLocale;

# cpanel - Cpanel/SetEnvLocale.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::SetEnvLocale

=head1 SYNOPSIS

    {
        # Sets all the locale environment variables to "C"
        my $env_locale = Cpanel::SetEnvLocale->new();

        # Run system commands & test results/errors
        # against English strings
    }

    # The environment locale is back to what it was before

=head1 DESCRIPTION

This provides a simple way set all the locale environment
variables when non-localized output from system commands or
external programs is desired or a specific output locale is
desired.

This avoids the need to individually set, then reset, each of the
system environment variables pertaining to locale.

=cut

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new( $locale_name )

Instantiates this class. While $obj lives, all the system locale
environment variables will be set to either the value set by
$locale_name (if set), or to "C" if $locale_name is not passed in.

=cut

use constant locale_env_vars => qw(LANG LANGUAGE LC_ALL LC_MESSAGES LC_CTYPE);

sub new ( $class, $locale_name = 'C' ) {

    my %old_vals = %ENV{ locale_env_vars() };

    foreach my $var ( locale_env_vars() ) {
        $ENV{$var} = $locale_name;
    }

    return bless \%old_vals, $class;
}

sub DESTROY ($self) {

    foreach my $var ( locale_env_vars() ) {
        $ENV{$var} = $self->{$var};
    }

    return;
}

1;
