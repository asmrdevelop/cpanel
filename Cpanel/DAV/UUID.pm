package Cpanel::DAV::UUID;

# cpanel - Cpanel/DAV/UUID.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Digest::SHA ();

#
# Given a WebDAV resource path and lock requestor/owner, generate
# a UUID mostly compliant with RFC 4918 section 20.7.  Despite the
# lack of EUI64 identifier in the host portion of the UUID, the
# value generated is likely not cryptographically sound and should
# not be used in production code outside of the limited realm of a
# WebDAV server implementation.
#
# Note that due to the nature of the underlying libc function rand(),
# it would be best that any concurrent WebDAV services built upon
# this package synchronize upon usages of this method.
#
# You *can* pass in additional salts; however, the tests indicate that this
# should not be necessary.
#
sub generate {
    return join '-', unpack( 'H8 H4 H4 H4 H12', Digest::SHA::sha1( join( q<>, @_, time(), rand(), $<, $$ ) ) );
}

1;

__END__
Copyright (c) 2010, cPanel, Inc. All rights reserved.
This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.
