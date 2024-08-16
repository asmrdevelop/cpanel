package Cpanel::Email::Exists;

# cpanel - Cpanel/Email/Exists.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel                               ();
use Cpanel::Autodie                      ();
use Cpanel::Exception                    ();
use Cpanel::Validate::FilesystemNodeName ();

=head1 NAME

Cpanel::Email::Exists

=head1 DESCRIPTION

Routines use to detect if an email account exists on the system.


=head1 SYNOPSIS

  # Assume exists@domain.tld exists, this doesn't die
  pop_exists_or_die('exists', 'domain.tld');

  # Assume noexists@domain.tld does not exists, this does die
  pop_exists_or_die('noexists', 'domain.tld');

=head1 DEVELOPER NOTES

These methods were extracted from Cpanel::API::Email so that other modules could
perform validation of the existence of an email virtual user on the system without
running expensive listing api calls in the Email subsystem.

=head1 FUNCTIONS

=head2 Cpanel::Mail::Exists::pop_exists_or_die

Checks if the requested pop account exists on the system. Dies if it does not exist.

=head3 ARGUMENTS

    user   - string - user to check
    domain - string - domain to check

=head3 THROWS

    Cpanel::Exception::Email::AccountNotFound

=cut

sub pop_exists_or_die {
    my ( $user, $domain ) = @_;

    if ( !length $domain ) {
        my $suppress = Cpanel::Exception::get_stack_trace_suppressor();

        die Cpanel::Exception::create( 'Email::AccountNotFound', [ name => $user ] );
    }
    elsif ( !pop_exists( $user, $domain ) ) {
        my $suppress = Cpanel::Exception::get_stack_trace_suppressor();

        die Cpanel::Exception::create( 'Email::AccountNotFound', [ name => "$user\@$domain" ] );
    }

    return;
}

=head2 Cpanel::Mail::Exists::pop_exists

Checks if the requested pop account exists on the system.

=head3 ARGUMENTS

    user   - string - user to check
    domain - string - domain to check

=head3 RETURNS

    boolean - truthy if the pop account exists, falsey otherwise.

=cut

sub pop_exists {
    my ( $user, $domain ) = @_;
    my $ret = 0;
    if ( Cpanel::Validate::FilesystemNodeName::is_valid($user) ) {
        if ( Cpanel::Validate::FilesystemNodeName::is_valid($domain) ) {
            $ret = _pop_dir_exists( $user, $domain ) ? 1 : 0;
        }
    }
    return $ret;
}

=head2 Cpanel::Mail::Exists::_pop_dir_exists

Checks if the requested pop account directory exists on the system.

=head3 ARGUMENTS

    user   - string - user to check
    domain - string - domain to check

=head3 RETURNS

    truthy if it exist, falsey otherwise

=cut

sub _pop_dir_exists {
    my ( $email, $domain ) = @_;

    my $homedir = $Cpanel::homedir || do {
        die "No homedir, and running as root!" if !$>;
        ( getpwuid $> )[7];
    };

    die "No homedir detected!" if !$homedir;

    return Cpanel::Autodie::exists("$homedir/mail/$domain/$email");
}

=head2 Cpanel::Mail::Exists::pop_exists_specify_homedir

Checks if the requested pop account exists on the system.

=head3 ARGUMENTS

    user    - string - user to check
    domain  - string - domain to check
    homedir - string - home directory of user

=head3 RETURNS

    boolean - truthy if the pop account exists, falsey otherwise.

=cut

sub pop_exists_specify_homedir {
    my ( $user, $domain, $homedir ) = @_;

    my $ret = 0;
    if ( Cpanel::Validate::FilesystemNodeName::is_valid($user) ) {
        if ( Cpanel::Validate::FilesystemNodeName::is_valid($domain) ) {
            $ret = Cpanel::Autodie::exists("$homedir/mail/$domain/$user") ? 1 : 0;
        }
    }
    return $ret;
}

1;
