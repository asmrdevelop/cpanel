package Install::LetsEncrypt;

#                                      Copyright 2024 WebPros International, LLC
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited.

use cPstrict;

=encoding utf-8

=head1 NAME

Install::LetsEncrypt

=head1 DESCRIPTION

A task to install AutoSSL’s L<Let’s Encrypt|https://letsencrypt.org>
provider at update time. Extends L<Cpanel::Task>.

=over

=item Type: Sanity

=item Frequency: always

=item EOL: never

=back

=cut

exit __PACKAGE__->runtask() unless caller;

#----------------------------------------------------------------------

use parent qw( Cpanel::Task );

use Cpanel::Install::LetsEncrypt ();

use constant _INTERNAL_NAME => 'letsencrypt';
use constant _PROVIDER_NAME => 'LetsEncrypt';
use constant _CPANEL_NAME   => 'cPanel';

#----------------------------------------------------------------------

=head1 METHODS

=head2 I<OBJ>->perform()

See parent class.

=cut

sub perform ($self) {

    $self->do_once(
        version => '11.120_' . _INTERNAL_NAME,
        eol     => 'never',
        code    => \&_enable_autossl,
    );

    return;
}

sub _enable_autossl {

    # Already enabled during initial install.
    return if $ENV{'CPANEL_BASE_INSTALL'};

    require Cpanel::SSL::Auto::Config::Read;
    my $enabled_provider = eval { Cpanel::SSL::Auto::Config::Read->new()->get_provider() } || q{};

    # Don't try to switch to Let's Encrypt unless the enabled provider is the
    # deprecated cPanel provider.
    return unless $enabled_provider eq _CPANEL_NAME;

    Cpanel::Install::LetsEncrypt::install_and_activate();

    return;
}

1;
