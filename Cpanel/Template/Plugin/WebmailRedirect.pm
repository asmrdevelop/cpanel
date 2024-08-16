package Cpanel::Template::Plugin::WebmailRedirect;

# cpanel - Cpanel/Template/Plugin/WebmailRedirect.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Template::Plugin::WebmailRedirect

=head1 DESCRIPTION

This plugin facilitates redirecting a cPanel user to a Webmail session
via Template Toolkit.

=cut

#----------------------------------------------------------------------

use parent qw( Template::Plugin );

use Cpanel::API             ();
use Cpanel::WarnToLog       ();
use Cpanel::WebmailRedirect ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 redirect_data = WebmailRedirect.create_webmail_session( username, return_url )

A thin wrapper around L<Cpanel::WebmailRedirect>’s C<create_webmail_session()>.
See that function’s documentation for more details.

All warnings are sent to the server log.

=cut

sub create_webmail_session ( $self, $username, $return_url ) {
    my $warn_catcher = Cpanel::WarnToLog->new();

    return Cpanel::WebmailRedirect::create_webmail_session(
        $username,
        \&Cpanel::API::execute_or_die,
        return_url => $return_url,
    );
}

1;
