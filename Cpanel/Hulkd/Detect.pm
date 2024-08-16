package Cpanel::Hulkd::Detect;

# cpanel - Cpanel/Hulkd/Detect.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Hulkd;    # or use base 'Cpanel::Hulkd' if it use'd instead, gets tricksy

sub detective_array {
    my ($hulk) = @_;
    return sort keys %{ $hulk->{'detectives'} };
}

sub ensure_all_detectives {
    my ($hulk) = @_;
    for my $detect ( $hulk->detective_array() ) {
        $hulk->ensure_detective($detect);
    }
}

sub get_zero_string {
    my ( $hulk, $detective ) = @_;
    return "cPhulkd $detective";

}

sub set_pid_for {
    my ( $hulk, $detective, $pid ) = @_;
    $hulk->{'detectives'}{$detective} = $pid;
}

sub get_pid_for {
    my ( $hulk, $detective ) = @_;
    return $hulk->{'detectives'}{$detective};
}

sub kill_detectives { return; }

sub ensure_detective {

    #disabled
    return;
}

sub load_detectives { return; }

1;
