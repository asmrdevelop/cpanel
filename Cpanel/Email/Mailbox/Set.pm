package Cpanel::Email::Mailbox::Set;

# cpanel - Cpanel/Email/Mailbox/Set.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::CpUserGuard ();
use Cpanel::Userdomains         ();
use Cpanel::Dovecot::Config     ();
use Cpanel::Exception           ();

sub set_users_mailbox_format {
    my (%opts) = @_;

    foreach my $required (qw(user format)) {
        if ( !length $opts{$required} ) {
            die Cpanel::Exception::create( 'MissingParameter', [ 'name' => $required ] );
        }
    }

    my $user   = $opts{'user'};
    my $format = $opts{'format'};

    if ( !$Cpanel::Dovecot::Config::KNOWN_FORMATS{$format} ) {
        die Cpanel::Exception::create( 'InvalidParameter', "The “[_1]” parameter must be one of the following: [join,~, ,_2]", [ $format, [ sort keys %Cpanel::Dovecot::Config::KNOWN_FORMATS ] ] );

    }

    my $cpuser_guard = Cpanel::Config::CpUserGuard->new($user);
    $cpuser_guard->{'data'}->{'MAILBOX_FORMAT'} = $format;
    $cpuser_guard->save();

    Cpanel::Userdomains::updateuserdomains();

    return 1;
}

1;
