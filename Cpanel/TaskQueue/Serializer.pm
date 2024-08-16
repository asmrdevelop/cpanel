package Cpanel::TaskQueue::Serializer;

# cpanel - Cpanel/TaskQueue/Serializer.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::JSON ();

use constant SERIALIZER_FILE_EXTENSION => 'json';

# load - needs to conform to a Cpanel::TaskQueue::Serializer object specs
sub load ( $class, $fh ) {
    my $ref = Cpanel::JSON::LoadFile($fh);
    return undef if !$ref || !ref $ref;
    return @{$ref};
}

# save - needs to conform to a Cpanel::TaskQueue::Serializer object specs
sub save ( $class, $fh, @text ) {
    return Cpanel::JSON::DumpFile( $fh, \@text );
}

# filename - needs to conform to a Cpanel::TaskQueue::Serializer object specs
sub filename ( $class, $stub ) {
    return $stub . '.' . SERIALIZER_FILE_EXTENSION;
}

# utf-8 roundtrip safe when used with the Cpanel::ServerTasks::encode_param method.
sub decode_param ($encoded_string) {
    require Cpanel::Encoder::URI;
    require Cpanel::AdminBin::Serializer;
    my $json = Cpanel::Encoder::URI::uri_decode_str($encoded_string);
    return Cpanel::AdminBin::Serializer::Load($json);
}

1;
