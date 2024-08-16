
# cpanel - Cpanel/iContact/Provider.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::iContact::Provider;

use strict;
use warnings;

###########################################################################
#
# Method:
#   new
#
# Description:
#    A base class for Cpanel::iContact::Provider:: objects
#
# Parameters:
#
#   attach_files   - An arrayref of files to attach as defined by
#   (optional)       Cpanel::iContact::normalize_attach_files
#
#   contact        - A hashref of contact settings loaded by
#   (required)       Cpanel::iContact such as the level (importance)
#                    user, password, etc
#
#   args           - The content of the iContact notification
#   (required)       in the form of arguments acceptable to
#                    Cpanel::Email::Object
#
#
# Exceptions:
#   MissingParameter - When contact or args are missing
#
# Returns:
#   A Cpanel::iContact::Provider::... object
#
sub new {
    my ( $class, %OPTS ) = @_;

    foreach my $required (qw(contact args)) {
        if ( !$OPTS{$required} ) {
            require Cpanel::Exception;
            die Cpanel::Exception::create( 'MissingParameter', [ 'name' => $required ] );
        }
    }

    return bless \%OPTS, $class;
}

sub email_message {
    my ( $self, %OPTS ) = @_;

    require Cpanel::iContact::Email;
    require Cpanel::Email::Send;
    require Cpanel::ServiceAuth;

    # We use SMTP auth to decrease the chance that an
    # iContact message will end up in the SPAM or Junk
    # folders since it will show up as smtpa instead of
    # smtp in the headers which generally results in
    # better treatment of the message.
    my $auth = Cpanel::ServiceAuth->new('icontact');
    $auth->generate_authkeys_if_missing();
    my $user = $auth->fetch_userkey();
    my $pass = $auth->fetch_passkey();

    Cpanel::iContact::Email::convert_attach_files_to_attachments( \%OPTS );

    return Cpanel::Email::Send::email_message(
        \%OPTS,
        {
            'smtp_user' => "__cpanel__service__auth__icontact__$user",
            'smtp_pass' => $pass,
        }
    );
}

# interface stub - subclasses should implement for a shared interface
sub send {
    die 'ABSTRACT';
}

1;
