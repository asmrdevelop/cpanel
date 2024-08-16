package Install::ExternalAuth;

# cpanel - install/ExternalAuth.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Task );

our $VERSION = '1.0';

=head1 DESCRIPTION

    Create directories required by openid

=over 1

=item Type: Fresh Install

=item Frequency: once

=item EOL: never

=back

=cut

exit __PACKAGE__->runtask() unless caller;

sub new {
    my $proto = shift;
    my $self  = $proto->SUPER::new;

    $self->set_internal_name('externalauth');

    return $self;
}

sub perform {
    my $self = shift;

    $self->do_once(
        version => '11.53.9999.34',
        eol     => 'never',
        code    => sub {
            require Cpanel::Security::Authn::LinkDB;
            require Cpanel::Security::Authn::OpenIdConnect;
            require Cpanel::Security::Authn::Provider::OpenIdConnectBase;
            require Cpanel::Security::Authn::User;

            Cpanel::Security::Authn::OpenIdConnect::create_storage_directories_if_missing();
            Cpanel::Security::Authn::LinkDB::create_storage_directories_if_missing('openid_connect');
            Cpanel::Security::Authn::Provider::OpenIdConnectBase::create_storage_directories_if_missing();
            Cpanel::Security::Authn::User::create_storage_directories_if_missing();
        }
    );
    return 1;
}

1;

__END__
