package Cpanel::PasswdStrength::Generate;

# cpanel - Cpanel/PasswdStrength/Generate.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

my %CHRSETS = (
    'uppercase' => [ ( 65 .. 90 ) ],     # A - Z
    'lowercase' => [ ( 97 .. 122 ) ],    # a - z
    'numbers'   => [ ( 48 .. 57 ) ],     # 0 - 9
    'symbols'   => [
        33,                # !
        ( 36 .. 38 ),      # $%&
        ( 40 .. 47 ),      # ()*+,-./
        58,                # :
        ( 60 .. 64 ),      # <=>?@
        ( 123 .. 126 ),    # {|}~
    ],
    'othersymbols' => [ 34, 35, 39, 59 ]    # #"';
);

sub generate_password {
    my ( $length, %opts ) = @_;
    my $chrs_ref = get_chr_array_ref(%opts);
    my $pw;
    for ( 1 .. $length ) {
        $pw .= ${$chrs_ref}[ rand( @{$chrs_ref} ) ];
    }
    return $pw;
}

sub get_chr_string {
    my %opts = @_;
    my $txt  = '';
    foreach my $chrset ( keys %CHRSETS ) {
        next if $opts{"no_$chrset"};
        foreach my $chlist ( @{ $CHRSETS{$chrset} } ) {
            foreach my $chr ($chlist) {
                $txt .= chr $chr;
            }
        }
    }
    return $txt;
}

sub get_chr_array_ref {
    my %opts = @_;
    my @characters;
    foreach my $chrset ( keys %CHRSETS ) {
        next if $opts{"no_$chrset"};
        foreach my $chlist ( @{ $CHRSETS{$chrset} } ) {
            foreach my $chr ($chlist) {
                push( @characters, chr($chr) );
            }
        }
    }
    return \@characters;
}

1;
