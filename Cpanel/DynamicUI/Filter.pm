package Cpanel::DynamicUI::Filter;

# cpanel - Cpanel/DynamicUI/Filter.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=head1 NAME

Cpanel::DynamicUI::Filter

=head1 DESCRIPTION

Provide some shared helpers to filter on DynamicUI items.

=cut

=head1 SYNOPSIS

    use Cpanel::DynamicUI::Filter ();

    'skip' if Cpanel::DynamicUI::Filter::is_valid_entry( $item );
    ...

=cut

=head1 FUNCTIONS

=head2 is_valid_entry( $item )

=head3 Purpose

Check if a DynamicUI menu item can be displayed in the UI.

=head3 Arguments

=over

=item $item: a hashref representing the entry element.
This should have been parsed by L<Cpanel::DynamicUI::Parser>

=back

=head3 Returns

Returns a boolean

=over

=item true: the entry is valid and can be displayed to the user

=item false: we should hide this entry to the user

=back

=cut

sub is_valid_entry ($item) {

    return 1 if _check_cpanel_os_check($item)    #
      && _check_file_check($item);

    return 0;
}

sub _check_cpanel_os_check ($item) {
    return 1 unless ref $item && length $item->{'cpanel_os_check'};

    require Cpanel::OS;                          # PPI USE OK -- used just after

    my @checks = split( ',', $item->{'cpanel_os_check'} );
    foreach my $check (@checks) {
        my ( $key, $value ) = split( '=', $check, 2 );
        my $current = eval qq[ Cpanel::OS::$key() ] // '';    ## no critic qw(ProhibitStringyEval)
        return 0 unless $current eq $value;
    }

    return 1;
}

sub _check_file_check ($item) {
    return 1 unless ref $item && length $item->{'file_check'};

    my @checks = split( ',', $item->{'file_check'} );
    foreach my $check (@checks) {
        my $positive_check = 1;
        $check =~ s{^\s+}{};
        $check =~ s{\s+$}{};
        $positive_check = 0 if $check =~ s{^!}{};
        if ($positive_check) {    # file needs to be there to continue
            return 0 if !-e $check;
        }
        else {                    # file needs to be missing to continue
            return 0 if -e $check;
        }
    }

    return 1;
}

1;
