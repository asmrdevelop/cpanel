package Cpanel::CommandStream::Serializer::JSON;

# cpanel - Cpanel/CommandStream/Serializer/JSON.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::CommandStream::Serializer::JSON - JSON for CommandStream

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::CommandStream::Serializer';

use Cpanel::JSON ();

#----------------------------------------------------------------------

sub _serialize ( $, $struct ) {

    # Since JSON is meant for interactive use rather than production,
    # output canonical and add whitespace to make reading easier.
    return ( ' ' x 2 ) . Cpanel::JSON::canonical_dump($struct) . $/;
}

sub _deserialize ( $, $buf_sr ) {
    return Cpanel::JSON::Load($$buf_sr);
}

1;
