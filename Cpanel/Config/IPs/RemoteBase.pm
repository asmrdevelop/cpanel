package Cpanel::Config::IPs::RemoteBase;

# cpanel - Cpanel/Config/IPs/RemoteBase.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Config::IPs::RemoteBase

=head1 SYNOPSIS

See L<Cpanel::Config::IPs::RemoteMail>.

=head1 DESCRIPTION

This base class encapsulates logic for reading certain remote-IP datastores.
(As of this writing, that’s remote-mail and remote-DNS.)

=head1 SUBCLASS INTERFACE

Subclasses B<must> provide a C<_PATH()> method/constant that returns
the datastore’s filesystem path.

=cut

#----------------------------------------------------------------------

use Cpanel::LoadFile ();

#----------------------------------------------------------------------

=head1 CLASS METHODS

=head2 $ips_ar = I<CLASS>->read()

Returns the datastore’s contents as an array reference.
If the datastore doesn’t exist, the referent array will be empty.
If any other failure prevents loading of the datastore, an appropriate
exception is thrown.

=cut

sub read ($class) {
    my $txt = Cpanel::LoadFile::load_if_exists( $class->_PATH() );

    my @contents;

    if ( length $txt ) {
        @contents = grep { $_ } split m<\n>, $txt;
    }

    return \@contents;
}

#----------------------------------------------------------------------

=head2 $path = I<CLASS>->PATH()

A public interface to the datastore’s on-disk path.

Ideally nothing would call this, but we have backup functions that
expect to do backups by copying files, and having this here avoids the
need to alter those.

Please don’t add additional calls to this method.

=cut

sub PATH ($class) {
    return $class->_PATH();
}

1;
