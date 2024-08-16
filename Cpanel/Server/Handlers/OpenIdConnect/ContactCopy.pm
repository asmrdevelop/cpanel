package Cpanel::Server::Handlers::OpenIdConnect::ContactCopy;

# cpanel - Cpanel/Server/Handlers/OpenIdConnect/ContactCopy.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# NOTE: Nothing here propagates an exception, by design;
# instead, all errors are converted to warn()s.
#----------------------------------------------------------------------

use strict;
use warnings;

use Try::Tiny;

use Cpanel::Config::LoadCpUserFile ();
use Cpanel::LoadModule             ();

#For when you have the email address already.
sub save_user_contact_email_if_needed {
    my ( $username, $email_addr ) = @_;

    if ( contact_email_needs_update($username) ) {
        save_user_contact_email(
            $username,
            $email_addr,
        );
    }

    return;
}

sub contact_email_needs_update {
    my ($username) = @_;

    if ( $username !~ tr<@><> && $username ne 'root' ) {
        my $cpuser;
        try {
            $cpuser = Cpanel::Config::LoadCpUserFile::load_or_die($username);
        }
        catch {
            warn "Failed to load cpuser data for “$username”: $_";
        };

        if ( $cpuser && !$cpuser->{DEMO} ) {
            return !$cpuser->contact_emails_ar()->@* || 0;
        }
    }

    return undef;
}

sub save_user_contact_email {
    my ( $username, $email_addr ) = @_;

    try {
        require Cpanel::Config::CpUserGuard;
        my $cpguard = Cpanel::Config::CpUserGuard->new($username);

        require Cpanel::Config::CpUser::Object::Update;
        Cpanel::Config::CpUser::Object::Update::set_contact_emails(
            $cpguard->{'data'},
            [],    # We should do this only if the account has no contact emails.
            [$email_addr],
        );

        $cpguard->save();
    }
    catch {
        warn sprintf "%s: %s", ( caller 0 )[3], $_;
    };

    return;
}

1;
