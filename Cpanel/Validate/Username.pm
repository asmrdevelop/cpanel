package Cpanel::Validate::Username;

# cpanel - Cpanel/Validate/Username.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::DB::Prefix::Conf         ();
use Cpanel::Exception                ();
use Cpanel::IO                       ();
use Cpanel::Validate::Username::Core ();
use Cpanel::Validate::Username::Mode ();

our $VERSION = 1.4;

our ( $MAX_LENGTH, $MAX_SYSTEM_USERNAME_LENGTH );
*MAX_LENGTH                 = \$Cpanel::Validate::Username::Core::MAX_LENGTH;
*MAX_SYSTEM_USERNAME_LENGTH = \$Cpanel::Validate::Username::Core::MAX_SYSTEM_USERNAME_LENGTH;

my $logger;

*list_reserved_usernames         = *Cpanel::Validate::Username::Core::list_reserved_usernames;
*list_reserved_username_patterns = *Cpanel::Validate::Username::Core::list_reserved_username_patterns;

*get_system_username_regexp_str = *Cpanel::Validate::Username::Core::get_system_username_regexp_str;
*get_regexp_str                 = *Cpanel::Validate::Username::Core::get_regexp_str;

#Validates that a string is a valid username per current system configuration.
#Converting this to a wrapper to allow it to be pulled based on global in_transfer_mode
#while allowing it to be pulled via make_strict_regexp_str directly with param
sub get_strict_regexp_str {
    my $for_transfer = Cpanel::Validate::Username::Mode::in_transfer_mode();
    return make_strict_regexp_str($for_transfer);
}

# Creates validation string to be used in for username validation
# Created to allow flexible for_transfer value specifically when used in
#   js validation in the transfer tool
sub make_strict_regexp_str {
    my $for_transfer  = shift;                        #boolean representing but not necessarily in_transfer_mode()
    my $special_chars = $for_transfer ? '-.' : q{};

    # underscore is valid only during transfer or if database_prefix is disabled
    $special_chars .= '\_' if $for_transfer || !Cpanel::DB::Prefix::Conf::use_prefix();

    # Before 11.42, underscore was valid only during transfer or if database_prefix is disabled.
    # Since 11.44, though, underscore is always valid, regardless of database_prefix.
    my $chars = "[${special_chars}a-z0-9]";

    my $len = "{1,$MAX_LENGTH}";

    return '^' . Cpanel::Validate::Username::Core::_regexp_lead() . $chars . $len . '$';
}

*is_valid_system_username = *Cpanel::Validate::Username::Core::is_valid_system_username;
*is_valid                 = *Cpanel::Validate::Username::Core::is_valid;

#This allows usernames that are only permissible in transfers,
#which is a few more things than account creation allows.
#
sub validate_or_die {
    my ($specimen) = @_;

    if ( !is_valid($specimen) ) {
        die Cpanel::Exception::create( 'InvalidUsername', [ value => $specimen ] );
    }

    return 1;
}

sub user_exists_or_die {
    my ($specimen) = @_;

    if ( !user_exists($specimen) ) {
        die Cpanel::Exception::create( 'UserNotFound', 'This system does not contain a user named “[_1]”.', [$specimen] );
    }

    return 1;
}

#for validating NEW (non-tranfer) account names
sub is_strictly_valid {
    return if !defined $_[0];

    my $regexp = get_strict_regexp_str();

    return $_[0] =~ m{$regexp};
}

*normalize               = *Cpanel::Validate::Username::Core::normalize;
*scrub                   = *Cpanel::Validate::Username::Core::scrub;
*reserved_username_check = *Cpanel::Validate::Username::Core::reserved_username_check;

sub user_exists  { _pw_exists( $_[0], '/etc/passwd' ) }
sub group_exists { _pw_exists( $_[0], '/etc/group' ) }

sub _pw_exists {
    my ( $user, $file ) = @_;
    if ( !$user || !length $file ) {
        _log_warn('Missing or invalid argument');
        return;
    }

    local $!;

    my $user_match = qr/\n\Q$user\E:/s;
    if ( open my $pw_fh, '<', $file ) {
        while ( my $block = Cpanel::IO::read_bytes_to_end_of_line( $pw_fh, 65535 ) ) {
            $block = "\n" . $block;    # need a \n for our regex to match -- we use /s since is much faster than /m
            if ( $block =~ $user_match ) {
                close $pw_fh;
                return 1;
            }
        }

        if ($!) {
            _log_warn("Assuming pw user “$user” exists. Failed to read “$file”: $!");
            return 1;
        }

        close $pw_fh or _log_warn("Failed to close “$file”: $!");
    }
    else {
        _log_warn("Assuming pw user “$user” exists. Failed to open “$file” for reading: $!");
        return 1;    # If we can't verify then say it exists
    }
    return;
}

sub _log_warn {
    my ($msg) = @_;

    require Cpanel::Logger;
    $logger ||= Cpanel::Logger->new();
    $logger->warn($msg);

    return;
}

1;
