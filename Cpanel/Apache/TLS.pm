package Cpanel::Apache::TLS;

# cpanel - Cpanel/Apache/TLS.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Apache::TLS - Apache’s SSL/TLS certificate datastore

=head1 SYNOPSIS

    #Note that get_tls_domains() doesn’t work.
    @vhosts = Cpanel::Apache::TLS->get_tls_vhosts()

    #See Cpanel::Domain::TLS for more examples.

=head1 DESCRIPTION

Most SSL-capable services reference cPanel’s “Domain TLS” datastore for SSL
certificates. These services also have the desirable quality of indexing
SSL certificates by requested domain (i.e., the SNI string).

Apache is different: rather than indexing SSL certificates by requested
domain, Apache indexes by the virtual host that matches the requested
domain. Each domain on a virtual host, thus, must serve up the same
certificate as the other domains on that same virtual host. It’s awkward,
but it is what it is.

Because of this limitation, user SSL installations happen to Apache first,
and then the certificate for each Apache virtual host is copied over to
Domain TLS for whichever of the virtual host’s domains that the certificate
actually secures. Because the user installations see Apache first, it’s
useful to index the Apache-installed certificates to have quick access to
such items as each certificate’s encryption algorithm, etc.

Apache is also different in that, while certificates in Domain TLS B<must>
pass OpenSSL verification prior to installation, cPanel allows certain types
of SSL verification errors not to prohibit installation of a certificate
in Apache.

For these reasons, Apache has its own SSL certificate datastore, separate
from that for other SSL-capable services, called “Apache TLS”.

This module inherits from L<Cpanel::Domain::TLS>, with the one exception that
the C<get_tls_domains()> method throws an exception (because Apache’s SSL/TLS
configuration indexes on virtual hosts, not domains). All other methods from
L<Cpanel::Domain::TLS> work the same way, except that the datastore indexes
by vhost names rather than “FQDN”s.

=cut

use parent qw( Cpanel::Domain::TLS );

use Cpanel::Domain::TLS ();    #keep cplint happy..

use constant {
    _ENTRY_TYPE => 'vhost name',
};

our $_BASE_PATH;

BEGIN {
    $_BASE_PATH = '/var/cpanel/ssl/apache_tls';
}

=head1 METHODS

See L<Cpanel::Domain::TLS> for most methods you’d want to call;
additionally there is:

=cut

#----------------------------------------------------------------------

=head2 @vhost_names = I<CLASS>->get_tls_vhosts()

Returns the names of Apache virtual hosts that have SSL/TLS installed.
(No order is defined.)

=cut

# NB: Defined as coderef so that a mock of get_tls_vhosts()
# doesn’t also inadvertently mock get_tls_domains().
*get_tls_vhosts = \&Cpanel::Domain::TLS::get_tls_domains;

#----------------------------------------------------------------------

=head2 $path = I<CLASS>->BASE_PATH()

Exposes the filesystem base path. Try not to use this unless you know
you need it.

=cut

sub BASE_PATH { return $_BASE_PATH }

#----------------------------------------------------------------------

=head2 I<CLASS>->get_tls_domains()

As described above, this always C<die()>s.

=cut

sub get_tls_domains { die 'not domains; vhosts!' }

#----------------------------------------------------------------------

#We don’t actually need to override _verify_entry, but this comment
#is here as a reminder that vhost names aren’t necessarily forever-and-ever
#tied to domain names.
#_verify_entry = __PACKAGE__->SUPER::can('_verify_entry');

1;
