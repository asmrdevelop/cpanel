#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - base/backend/emailsetup-ios.cgi         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Try::Tiny;

use Cpanel                        ();
use Cpanel::Exception             ();
use Cpanel::Form                  ();
use Cpanel::Locale                ();
use Cpanel::Logger                ();
use Cpanel::Validate::Username    ();
use Cpanel::Validate::EmailCpanel ();
use Cpanel::AdminBin::Call        ();
use Cpanel::Email::Setup          ();
use Cpanel::Encoder::Tiny         ();

#----------------------------------------------------------------------
# inputs:
#
#   acct              - (string) the email account name.
#
#   usessl            - (optional, boolean) whether to a secure connection.
#                       A value of 0 means no SSL, while a value of 1 means to use SSL.
#                       If it isn't entered this will default to 0.
#----------------------------------------------------------------------

# Must come before locale handle.
Cpanel::initcp();

my $CRLF = "\r\n";

my (%FORM) = Cpanel::Form::parseform();
my $logger;
my $locale = Cpanel::Locale->get_handle();

my $account = $FORM{'acct'};
my $use_ssl = $FORM{'usessl'} ? 1 : 0;

if ( !$account || !( Cpanel::Validate::EmailCpanel::is_valid($account) || Cpanel::Validate::Username::is_valid_system_username($account) ) ) {
    _display_error( $locale->maketext('Invalid Account'), $locale->maketext( '“[_1]” is not a valid account name.', $account ) );
}

my $props    = Cpanel::Email::Setup::get_account_properties( $account, $use_ssl );
my $fileName = $props->{'displayname'} . '.mobileconfig';
my $response;

try {
    $response = Cpanel::AdminBin::Call::call(
        'Cpanel',
        'autoconfig_call',
        'GENERATE_MOBILECONFIG',
        {
            'account'                   => $account,
            'use_ssl'                   => $use_ssl,
            'selected_account_services' => 'email'
        }
    );
}
catch {
    $logger ||= Cpanel::Logger->new();
    $logger->warn( Cpanel::Exception::get_string($_) );
    _display_error( $locale->maketext('Internal Error'), Cpanel::Exception::get_string($_) );
};

print map { "$_$CRLF" } (
    qq<Content-Type: application/x-apple-aspen-config; charset=utf-8; name="$fileName";>,
    qq<Content-Disposition: attachment; filename="$fileName";>,
    q<>,
    $response
);

#----------------------------------------------------------------------

sub _display_error {
    my ( $title, $body ) = @_;

    my $encoded_title = Cpanel::Encoder::Tiny::safe_html_encode_str($title);
    my $encoded_body  = Cpanel::Encoder::Tiny::safe_html_encode_str($body);
    print map { "$_$CRLF" } (
        'Content-type: text/html; charset=utf-8',
        q<>,
        "<html><head><title>$encoded_title</title></head><body>$encoded_body</body></html>",
    );

    exit;
}
