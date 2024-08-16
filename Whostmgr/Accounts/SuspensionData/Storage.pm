package Whostmgr::Accounts::SuspensionData::Storage;

# cpanel - Whostmgr/Accounts/SuspensionData/Storage.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Accounts::SuspensionData::Storage

=head1 SYNOPSIS

    my $info_hr = Whostmgr::Accounts::SuspensionData::Storage::parse_info($str);

    my $str = Whostmgr::Accounts::SuspensionData::Storage::serialize_info($info_hr);

=head1 DESCRIPTION

This module implements storage details (e.g., serialization) for the
account suspension datastores.

=cut

#----------------------------------------------------------------------

my @RECOGNIZED_KEYS = (
    'shell',
    'leave-ftp-accts-enabled',
);

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $info_hr = parse_info( $BUFFER )

Parses the string $BUFFER into a hash reference of the suspension info
(e.g., C<shell>).

=cut

sub parse_info ($info) {
    my %SUINFO;
    for my $line ( split m<\n>, $info ) {
        my ( $name, $value ) = split( /=/, $line, 2 );
        next if !length $name || !length $value;

        if ( grep { $_ eq $name } @RECOGNIZED_KEYS ) {
            $SUINFO{$name} = $value;
        }
        else {
            warn "Discarding unrecognized key ($name) in parse!";
        }
    }

    return \%SUINFO;
}

#----------------------------------------------------------------------

=head2 $buffer = serialize_info($info_hr)

The inverse operation from C<parse_info()>: takes a hash reference and
outputs a string.

=cut

sub serialize_info ($info_hr) {
    require Cpanel::Set;

    if ( my @bad = Cpanel::Set::difference( [ keys %$info_hr ], \@RECOGNIZED_KEYS ) ) {
        die "Unrecognized: @bad";
    }

    return join(
        "\n",
        ( map { "$_=$info_hr->{$_}" } sort keys %$info_hr ),
        q<>,
    );
}

1;
