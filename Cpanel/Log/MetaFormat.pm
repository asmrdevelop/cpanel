package Cpanel::Log::MetaFormat;

# cpanel - Cpanel/Log/MetaFormat.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::JSON ();

=encoding utf-8

=head1 NAME

Cpanel::Log::MetaFormat

=head1 SYNOPSIS

    Cpanel::Log::MetaFormat::encode_log( $string_variable );

    my $str = Cpanel::Log::MetaFormat::encode_log( 'name' => 'value' );

    #Any order should suffice, but having the metadata at the end
    #probably makes more sense.
    print $string_variable, $str;

=head1 DESCRIPTION

This module arose out of a desire for a quick, simple encoding for log data
that originates from outside cPanel’s code. That encoding also needed to
support transfer of metadata—so, for example, the log display can safely
transmit metadata such as whether the operation succeeded.

For log data that originates from within cPanel’s code, there are much
more complete options; see L<Cpanel::LogTailer> to get started.

=head1 FUNCTIONS

=head2 encode_log( STRING )

Encodes a string of log data. Note that the passed-in string is modified
in-place to save memory; hence, Perl will throw an exception if you
pass in a read-only string. Returns the number of substitutions made.

=cut

sub encode_log {
    return $_[0] =~ s<\.><..>mg;
}

=head2 encode_metadata( KEY => VALUE )

Returns a key/value pair string, encoded for this format.

=cut

sub encode_metadata {
    my ( $key, $value ) = @_;

    return sprintf ".%s\n", Cpanel::JSON::Dump( [ $key => $value ] );
}

1;
