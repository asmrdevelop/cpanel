
# cpanel - Cpanel/Validate/VirtualUsername.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Validate::VirtualUsername;

use strict;
use warnings;

use Cpanel::Exception                ();
use Cpanel::Validate::EmailLocalPart ();
use Cpanel::Validate::Domain         ();

sub is_valid {
    my ($full_username) = @_;    # including @domain, if applicable
    return eval { validate_or_die($full_username); 1 };
}

sub validate_or_die {
    my ($full_username) = @_;    # including @domain, if applicable

    if ( !length($full_username) ) {
        my $suppress = Cpanel::Exception::get_stack_trace_suppressor();
        die Cpanel::Exception::create( 'InvalidParameter', 'The username validation routine received an empty username.' );
    }

    if ( length($full_username) > 254 ) {
        my $suppress = Cpanel::Exception::get_stack_trace_suppressor();
        die Cpanel::Exception::create( 'InvalidParameter', 'The full username cannot exceed [numf,_1] characters.', [254] );    # In order to accommodate the SMTP limitation warned about in https://www.rfc-editor.org/errata_search.php?eid=1690
    }

    if ( $full_username =~ tr/@// ) {
        my ( $local_part, $domain ) = split /\@/, $full_username, 2;

        if ( length($local_part) > 64 ) {
            my $suppress = Cpanel::Exception::get_stack_trace_suppressor();
            die Cpanel::Exception::create( 'InvalidParameter', 'The local part cannot exceed [numf,_1] characters.', [64] );    # RFCs 5321, 3696, etc.
        }
        if ( !Cpanel::Validate::EmailLocalPart::is_valid($local_part) ) {
            my $suppress = Cpanel::Exception::get_stack_trace_suppressor();
            die Cpanel::Exception::create( 'InvalidParameter', 'The local part “[_1]” for user “[_2]” is invalid.', [ $local_part, $full_username ] );
        }
        if ( !Cpanel::Validate::Domain::is_valid_cpanel_domain($domain) ) {
            my $suppress = Cpanel::Exception::get_stack_trace_suppressor();
            die Cpanel::Exception::create( 'InvalidParameter', 'The domain “[_1]” for user “[_2]” is invalid.', [ $domain, $full_username ] );
        }
    }
    else {
        my $suppress = Cpanel::Exception::get_stack_trace_suppressor();
        die Cpanel::Exception::create( 'InvalidParameter', 'All virtual users must include both a local part and a domain.' );
    }
    return 1;
}

sub is_valid_for_creation {
    my ($full_username) = @_;    # including @domain, if applicable
    return eval { validate_for_creation_or_die($full_username); 1 };
}

sub validate_for_creation_or_die {
    my ($full_username) = @_;

    if ( !defined $full_username || !length $full_username ) {
        my $suppress = Cpanel::Exception::get_stack_trace_suppressor();
        die Cpanel::Exception::create( 'InvalidParameter', 'You must specify a username.' );
    }

    my ($local_part) = split /\@/, $full_username, 2;
    if ( $local_part !~ m{\A[a-zA-Z0-9.\-_]*\z} ) {    # allow empty since the VirtualUsername validation will catch that
        my $suppress = Cpanel::Exception::get_stack_trace_suppressor();
        die Cpanel::Exception::create( 'InvalidParameter', 'The local part can only contain letters [asis,(a-z)], numbers [asis,(0-9)], periods, hyphens [asis,(-)], and underscores [asis,(_)].' );    # Our own rule -- stricter than any RFC
    }

    return validate_or_die($full_username);
}

1;
