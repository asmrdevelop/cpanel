
# cpanel - Whostmgr/InitialWebsite/Create.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::InitialWebsite::Create;

use strict;
use warnings;

use Cpanel::Locale::Lazy 'lh';
use Whostmgr::InitialWebsite ();

=head1 NAME

Whostmgr::InitialWebsite::Create

=head1 DESCRIPTION

This module handles the creation of an initial website when first logging in to WHM
if the server owner has opted to use this mechanism.

=head1 SETUP

After booting your server, but prior to logging in to WHM, create a JSON file called
/var/cpanel/.create-website with the following structure:

  {
    "domain":   "example.com",
    "username": "example",
    "password": "yourPassword"
  }

Important: Because this file contains a password, make sure the file has 600 permissions.

The expectation is that this file will be automatically created by some other tool, like
a cloud instance manager, based on user inputs.


=head2 create()

Create the initial website based on the information defined in the /var/cpanel/.create-website
file. See the SETUP section above for more information on this.

=cut

sub create {
    if ( !$INC{'Whostmgr/Accounts/Create.pm'} ) {
        die 'Unshipped module Whostmgr::Accounts::Create must be preloaded by (compiled) caller';
    }

    require Cpanel::JSON;
    require Cpanel::iContact::Class::InitialWebsite::Creation;
    require Cpanel::Notify::Deferred;

    my $website_data = Cpanel::JSON::LoadFile(Whostmgr::InitialWebsite::CREATE_WEBSITE_FILE);
    for my $required_attribute (qw(domain username password)) {
        if ( !$website_data->{$required_attribute} ) {
            die lh()->maketext( 'To configure an initial website, you must provide the “[_1]” attribute.', $required_attribute );
        }
    }

    my ( $status, $reason, $output, $opref ) = Whostmgr::Accounts::Create::_createaccount(
        user                         => $website_data->{username},
        domain                       => $website_data->{domain},
        pass                         => $website_data->{password},
        plan                         => 'default',
        skip_password_strength_check => 1,
    );

    if ( !$status ) {
        die $reason;
    }

    my $login_url = _cpanel_login_url();

    Cpanel::Notify::Deferred::notify_without_triggering_subqueue(
        'class'            => 'InitialWebsite::Creation',
        'application'      => 'InitialWebsite::Creation',
        'constructor_args' => [

            # These two fields are required by FromUserAction
            origin            => 'WHM initial setup',
            source_ip_address => $ENV{REMOTE_ADDR},

            # These are required by InitialWebsite::Creation
            username  => $website_data->{username},
            domain    => $website_data->{domain},
            status    => $status,
            reason    => $reason,
            login_url => $login_url,
        ],
    );

    unlink Whostmgr::InitialWebsite::CREATE_WEBSITE_FILE;

    my $outcome = {
        created  => 1,
        username => $website_data->{username},
    };

    Cpanel::JSON::DumpFile(
        Whostmgr::InitialWebsite::CREATION_FILE,
        $outcome,
    );

    return $outcome;
}

sub _cpanel_login_url {
    require Cpanel::DIp::MainIP;
    require Cpanel::NAT;

    my $ip = Cpanel::NAT::get_public_ip( Cpanel::DIp::MainIP::getmainserverip() );

    return sprintf( 'https://%s:2083/', $ip );
}

1;
