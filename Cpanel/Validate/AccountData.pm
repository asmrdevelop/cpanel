package Cpanel::Validate::AccountData;

# cpanel - Cpanel/Validate/AccountData.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

our $ALLOW_VALID   = 0;
our $ALLOW_INVALID = 1;

use Cpanel::Locale                 ();
use Cpanel::Config::LoadCpUserFile ();
use Cpanel::Validate::EmailRFC     ();
use Cpanel::Validate::Username     ();

my $locale;

sub _locale {
    return $locale ||= Cpanel::Locale->get_handle();
}

###########################################################################
#
# Method:
#   generate_object_owner_validation
#
# Description:
#   This function provides a coderef that will check
#   a username or email address to see if it belongs
#   to a user
#
# Parameters:
#   user   - The user that will be checked to see if they own the object passed to the coderef
#   logger - An optional logger object that get
#
# Returns:
#   A code ref that accepts the following parameters:
#    to_check - The object (email or username) to check to see if it belows to the user
#    flags    - $ALLOW_INVALID or $ALLOW_VALID
#               When ALLOW_INVALID is passed any object that does not match a user or email
#               will return true.
#               When ALLOW_VALID is passed any object that does not match a user or email
#               will return false.
#
sub generate_object_owner_validation {
    my ( $user, $logger ) = @_;

    my $cpuserfile = Cpanel::Config::LoadCpUserFile::load($user);
    my %domains    = map { $_ => 1 } ( $cpuserfile->{'DOMAIN'}, @{ $cpuserfile->{'DOMAINS'} } );

    # check if the provided string is an account owned by the user
    return sub {
        my ( $to_check, $flags ) = @_;

        if ( !defined $to_check ) {
            return;
        }
        elsif ( $to_check =~ m{\s} ) {
            $logger->info( _locale()->maketext( "Rejecting data “[_1]” because it contains white space.", $to_check ) ) if $logger;
            return;
        }
        elsif ( $to_check eq $user ) {
            return 1;
        }
        elsif ( Cpanel::Validate::EmailRFC::is_valid($to_check) ) {
            my ( $dummy, $dom ) = Cpanel::Validate::EmailRFC::get_name_and_domain($to_check);
            return 1                                                                                                        if $domains{$dom};
            $logger->info( _locale()->maketext( "Rejecting data that belongs to “[_1]” instead of “[_2]”.", $dom, $user ) ) if $logger;
            return;
        }
        elsif ( Cpanel::Validate::Username::is_valid($to_check) ) {
            $logger->info( _locale()->maketext( "Rejecting data that belongs to “[_1]” instead of “[_2]”.", $to_check, $user ) ) if $logger;
            return 0;
        }
        elsif ( $flags && $flags & $ALLOW_INVALID ) {
            return 1;
        }
        else {
            # This does not match a username and might be something like
            # Mb7TPNHjNGjHPWHFq_UwDA1
            $logger->info( _locale()->maketext( "Rejecting data that belongs to “[_1]” instead of “[_2]”.", $to_check, $user ) ) if $logger;
            return 0;
        }
    }
}

1;
