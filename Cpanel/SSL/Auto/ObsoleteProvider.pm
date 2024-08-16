package Cpanel::SSL::Auto::ObsoleteProvider;

#                                      Copyright 2024 WebPros International, LLC
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited.

=encoding utf-8

=head1 NAME

Cpanel::SSL::Auto::ObsoleteProvider - base class for obsolete AutoSSL provider modules

=head1 SYNOPSIS

    package Cpanel::SSL::Auto::Provider::MySSLProvider;

    use parent qw( Cpanel::SSL::Auto::ObsoleteProvider );

    if ( $obj->CERTIFICATE_IS_FROM_HERE($pem) ) { ... }

=head1 DESCRIPTION

This class defines minimal functionality for obsolete AutoSSL provider modules.
The primary purpose of an obsolete provider module is to assist with the
transition to a replacement provider by "owning" and allowing identification of
certificates issued by the provider before it was removed.

You should never instantiate this class directly; instead, you should
create subclasses to define obsolete AutoSSL provider behavior, and instantiate
those modules

=head1 HOW TO MAKE A PROVIDER MODULE

The first requirement for provider modules is that they subclass this
module.

The provider module must be namespaced the same as non-obsolete modules under
C<Cpanel::SSL::Auto::Provider> and reside under one of these two
directories:

=over 4

=item C</usr/local/cpanel>: cPanel-provided modules

=item C</var/cpanel/perl>: Third-party modules

=back

For example, a third-party module “MikesSSL” would be named
C</var/cpanel/perl/Cpanel/SSL/Auto/Provider/MikesSSL.pm>.

=cut

#----------------------------------------------------------------------

use cPstrict;

use Cpanel::Exception ();

use parent qw( Cpanel::SSL::Auto::Provider );

#----------------------------------------------------------------------

use constant {
    is_obsolete => 1,
};

=head1 METHODS

=head2 _obsolete

When called, throws an exception stating the subclassed provider is obsolete.

=cut

sub _obsolete {
    my ($self) = @_;
    my $class  = ref($self) || $self;
    my $name   = ( $class =~ s<.+::><>r );
    die Cpanel::Exception->create( "The “[_1]” provider is obsolete and cannot be used to issue new certificates.", [$name] );
}

=head2 Overridden methods

=over

=item CAA_STRING

=item EXPORT_PROPERTIES

=item MAX_DOMAINS_PER_CERTIFICATE

=item PROPERTIES

=item RESET

=item SORT_VHOST_FQDNS

=item SPECS

=item handle_new_certificate

=item renew_ssl

=item renew_ssl_for_vhosts

=back

These override their parent method with a call to C<_obsolete>.

=cut

*CAA_STRING                  = *_obsolete;
*EXPORT_PROPERTIES           = *_obsolete;
*MAX_DOMAINS_PER_CERTIFICATE = *_obsolete;
*PROPERTIES                  = *_obsolete;
*RESET                       = *_obsolete;
*SORT_VHOST_FQDNS            = *_obsolete;
*SPECS                       = *_obsolete;
*handle_new_certificate      = *_obsolete;
*renew_ssl                   = *_obsolete;
*renew_ssl_for_vhosts        = *_obsolete;

1;
