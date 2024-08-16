package Cpanel::Resellers;

# cpanel - Cpanel/Resellers.pm                              Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)

use Cpanel::API               ();
use Cpanel::Themes::Available ();

our $VERSION = '1.4';

*api2_get_sub_accounts = *get_sub_accounts;

## DEPRECATED!
sub Resellers_accountlistopt {
    my $list_accounts = Cpanel::API::_execute( 'Resellers', 'list_accounts' );
    return unless ( defined $list_accounts->data() );

    ## note: removed a '|| []' inside the {...}; should not be needed anymore given the above
    # Reducing the number of prints is important with IO::Scalar in the mix
    print( map { sprintf( '<option%s value="%s">%s (%s)</option>', ( $_->{select} ? ' selected="selected"' : '' ), $_->{user}, $_->{domain}, $_->{user} ) } @{ $list_accounts->data() } );

    return;
}

sub Resellers_themelistopt {
    my $current_theme = $Cpanel::CPDATA{'RS'} // '';

    # Reducing the number of prints is important with IO::Scalar in the mix
    print(    #
        map { '<option' . ( $current_theme eq $_ ? ' selected="selected"' : '' ) . ' value="' . $_ . '">' . $_ . '</option>' }    #
          @{ scalar Cpanel::Themes::Available::get_available_themes() }                                                           #
    );
    return;
}

sub get_sub_accounts {
    my $list_accounts = Cpanel::API::_execute( 'Resellers', 'list_accounts' );
    return unless ( defined $list_accounts->data() );
    return $list_accounts;
}

our %API = (
    get_sub_accounts => { allow_demo => 1 },
);

sub api2 {
    my ($func) = @_;
    return { %{ $API{$func} } } if $API{$func};
    return;
}

1;
