package Cpanel::Email::UserForward;

# cpanel - Cpanel/Email/UserForward.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::EmailFunctions               ();
use Cpanel::Email::Utils                 ();
use Cpanel::PwCache                      ();
use Cpanel::Validate::Username           ();
use Cpanel::Validate::EmailRFC           ();
use Cpanel::AccessIds::ReducedPrivileges ();
use Cpanel::FileUtils::Write             ();
use Cpanel::StringFunc::Trim             ();
use Cpanel::Exception                    ();

our $DOT_FORWARD_FILENAME = '.forward';
our $ALIASES_FILE         = '/etc/aliases';
our $LOCALALIASES_FILE    = '/etc/localaliases';

###########################################################################
#
# Method:
#   get_user_email_forward_destination
#
# Description:
#    Find the current destination for a user's email forwarding
#
# Parameters:
#    user - The system user
#
# Returns:
#    EITHER:
#       - arrayref of the current destinations for a user's email forwarding
#       - empty string if the user's email is not forwarded
#
sub get_user_email_forward_destination {
    my (%OPTS) = @_;

    foreach my $param (qw(user)) {
        die Cpanel::Exception::create( 'MissingParameter', [ 'name' => $param ] ) if !defined $OPTS{$param};
    }
    my $user = $OPTS{'user'};

    # First check /etc/alaises ($ALIASES_FILE)
    # Second check /etc/localaliases ($LOCALALIASES_FILE)
    for my $file ( $ALIASES_FILE, $LOCALALIASES_FILE ) {
        my $aliases_ref = Cpanel::EmailFunctions::getaliasesfromfile($file);
        if ( exists $aliases_ref->{$user} && @{ $aliases_ref->{$user} } ) {
            return $aliases_ref->{$user};
        }
    }

    # Lastly we check for a $DOT_FORWARD_FILENAME file.
    my $forward_dests = _get_aliases_from_dotforward($user);
    if ( $forward_dests && @{$forward_dests} ) {
        return $forward_dests;
    }

    return '';
}

###########################################################################
#
# Method:
#   set_user_email_forward_destination
#
# Description:
#    Set a user's forwarding destination
#
# Parameters:
#    user       - The system user
#    forward_to - The destination to forward the users mail to.  If an empty string
#        is specified, forwarding is disabled.
#
# Exceptions:
#    If updating the alias file or writing the $DOT_FORWARD_FILENAME file fails,
#    an exception will be triggered.
#
# Returns:
#    1 - A valid destination was provided and forwarding has been setup
#    0 - An invalid destination was provided
#

sub set_user_email_forward_destination {
    my (%OPTS) = @_;

    foreach my $param (qw(user forward_to)) {
        die Cpanel::Exception::create( 'MissingParameter', [ 'name' => $param ] ) if !defined $OPTS{$param};
    }

    my $user    = $OPTS{'user'};
    my $forward = Cpanel::StringFunc::Trim::ws_trim( $OPTS{'forward_to'} );
    if ( length $forward ) {
        foreach my $email ( Cpanel::Email::Utils::get_forwarders_from_string($forward) ) {
            if ( !Cpanel::Validate::Username::is_valid($email) && !Cpanel::Validate::EmailRFC::is_valid($email) && $email !~ m{^\|} ) {
                die Cpanel::Exception::create( 'InvalidParameter', "“[_1]” in the “[_2]” parameter is not valid.", [ $email, 'forward' ] );
            }
        }
    }

    # Update /etc/aliases only if an entry already exists for the user
    my $aliases_ref = Cpanel::EmailFunctions::getaliasesfromfile($ALIASES_FILE);
    if ( exists $aliases_ref->{$user} ) {
        Cpanel::EmailFunctions::changealiasinfile( $user, $forward, $ALIASES_FILE );
    }

    # Always add to $LOCALALIASES_FILE
    Cpanel::EmailFunctions::changealiasinfile( $user, $forward, $LOCALALIASES_FILE );

    _update_dotforward_file( $user, $forward );

    return 1;
}

sub _get_aliases_from_dotforward {
    my ($user) = @_;
    my $user_forward_file = _get_user_forward_file_path($user);
    my $access_ids;
    if ( $user ne 'root' && $user_forward_file ne "/$DOT_FORWARD_FILENAME" ) {
        $access_ids = Cpanel::AccessIds::ReducedPrivileges->new($user);
    }
    return if !-e $user_forward_file;
    return [ Cpanel::EmailFunctions::getemailaddressfromfile($user_forward_file) ];
}

sub _update_dotforward_file {
    my ( $user, $forward ) = @_;
    my $user_forward_file = _get_user_forward_file_path($user);

    # In the event the $user has a non-existent homedir, like "nobody" on Ubuntu, _get_user_forward_file_path will return
    # an error message rather than a /full/path/to/$DOT_FORWARD_FILENAME . This should be safe to skip, and if we don't it
    # causes an error in WHM during the setup wizard. See HB-6140 for more details.
    if ( $user_forward_file !~ m/^\// ) {
        return 0;
    }
    my $access_ids;
    if ( $user ne 'root' && $user_forward_file ne "/$DOT_FORWARD_FILENAME" ) {
        $access_ids = Cpanel::AccessIds::ReducedPrivileges->new($user);
    }
    Cpanel::FileUtils::Write::overwrite( $user_forward_file, $forward . "\n" );
    return 1;
}

sub _get_user_forward_file_path {
    my ($user) = @_;
    my $user_homedir = Cpanel::PwCache::gethomedir($user) or die "Failed to fetch homedir for user: $user";
    if ( !-d $user_homedir ) {
        return "NO SUCH HOME DIRECTORY: $user_homedir\n";
    }
    my $fullpath = $user_homedir . "/$DOT_FORWARD_FILENAME";
    $fullpath =~ s{/+}{/}g;
    return $fullpath;
}

1;
