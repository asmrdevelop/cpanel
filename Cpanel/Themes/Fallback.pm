package Cpanel::Themes::Fallback;

# cpanel - Cpanel/Themes/Fallback.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

# the purpose of this module is describe the fallback logic as it applies to branding
# and various scenarios
#
# this module is included directly in cpsrvd meaning that any addtional imports
# should be carefully considered.

use Cpanel::Exception ();
use Cpanel::PwCache   ();

my @DEFAULT_PATH_ORDER = ( 'user', 'reseller', 'global', 'default' );

my %owner_homedir_cache;

=head1 NAME

Cpanel::Themes::Fallback

=head2 get_paths(%OPTS)
    Returns the paths that are used in the fallback list.

    Normally this will return the following directories:
        $user_homedir/var/cpanel/$subdir_specified_in_OPTS
        $owner_homedir/var/cpanel/reseller/$subdir_specified_in_OPTS
        /var/cpanel/customizations/$subdir_specified_in_OPTS
        /usr/local/cpanel/base/frontend/$theme_name/$subdir_specified_in_OPTS

    There are various options that can be passed to this method that change how it returns
    data (see parameter listing).

    params:

    required:
        username => the authenticated user's username
        owner    => the authenticated user's owner's username
        theme    => the authenticated user's theme

    optional:

        no_user_directory (INT BOOL)    => do not return the user's home diretory
        no_default_directory (INT BOOL) => do not return the global directory
        subdirectory (STRING)           => subdirectory to append to the end of the path
        return_hash  (BOOL) => return a set of key value pairs rather than an array of directories
        homedir (STRING)           => the homedir of the user

    returns:
        an array of directories (see above)
        OR
        hash of directories needing to be returned

=cut

sub get_paths {
    my (%OPTS) = @_;

    if ( !exists $OPTS{'username'} ) {
        return;
    }
    if ( !exists $OPTS{'owner'} ) {
        return;
    }
    if ( !exists $OPTS{'theme'} ) {
        return;
    }

    my $theme = $OPTS{'theme'};

    my $subdir        = exists $OPTS{'subdirectory'}                            ? '/' . $OPTS{'subdirectory'} : '';
    my $homedir       = ( $Cpanel::user && $Cpanel::user eq $OPTS{'username'} ) ? $Cpanel::homedir            : $OPTS{'homedir'};
    my $owner_homedir = $OPTS{'username'} eq $OPTS{'owner'}                     ? $homedir                    : undef;
    my $reseller      = exists $OPTS{'isreseller'} && $OPTS{'isreseller'}       ? $OPTS{'username'}           : $OPTS{'owner'};

    # TODO: optimize me.
    my %paths = (
        !$OPTS{'no_default_directory'} ? ( 'default' => get_default_directory( $theme, $subdir, $OPTS{'application'} ) ) : (),
        'global' => get_global_directory($subdir),
    );

    if ( $OPTS{'username'} eq $OPTS{'owner'} ) {
        $paths{'reseller'} = get_reseller_directory( $OPTS{'username'}, $subdir, $homedir );
        $paths{'user'}     = get_user_directory( $OPTS{'username'}, $subdir, $homedir ) unless $OPTS{'no_user_directory'};
    }
    else {
        $paths{'reseller'} = get_reseller_directory( $reseller, $subdir, $owner_homedir ) unless $reseller eq 'root';
        $paths{'user'}     = get_user_directory( $OPTS{'username'}, $subdir, $homedir )   unless $OPTS{'no_user_directory'};
    }

    foreach my $check (qw(user reseller global)) {
        delete $paths{$check} if !( $paths{$check} && -e $paths{$check} );
    }

    if ( $OPTS{'return_hash'} ) {
        return %paths;
    }

    return map { $paths{$_} || () } @DEFAULT_PATH_ORDER;
}

# return the order of the keys for the most default scenario
sub get_path_order {
    return @DEFAULT_PATH_ORDER;

}

# Get the subdirectory under the user's home directory
# This is useful when you are running as the user
# & you already have the homedir, but don't have privileges
# to run PwCache::getpwnam()
sub get_user_subdir {
    my ( $homedir, $subdir ) = @_;

    if ( !defined $homedir || !length $homedir ) {
        die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'homedir' ] );
    }

    $subdir //= '';
    return "${homedir}/var/cpanel${subdir}";
}

# return the user's directory
sub get_user_directory {
    my ( $username, $subdir, $user_homedir ) = @_;
    $user_homedir ||= Cpanel::PwCache::gethomedir($username);
    return get_user_subdir( $user_homedir, $subdir );
}

# return the reseller's directory
sub get_reseller_directory {
    my ( $owner, $subdir, $owner_homedir ) = @_;

    $subdir        ||= '';
    $owner_homedir ||= ( $owner_homedir_cache{$owner} ||= Cpanel::PwCache::gethomedir($owner) );
    return unless $owner_homedir;
    return "${owner_homedir}/var/cpanel/reseller${subdir}";
}

# get the global directory
sub get_global_directory {
    my ($subdir) = @_;
    return "/var/cpanel/customizations${subdir}";
}

=head2 get_default_directory(@OPTS)
    Returns the path to styles provided by cPanel for an application

    For cpanel or unspecified applications,
        /usr/local/cpanel/base/frontend/$theme_name/$subdir_specified_in_OPTS

    And for webmail,
        /usr/local/cpanel/base/webmail/$theme_name/$subdir_specified_in_OPTS

    params:

    required: NONE

    optional:

        theme  (STRING)   => user's theme
        subdir (STRING)   => styles directory under the theme's docroot
        app    (STRING)   => can be either webmail, cpanel, or unspecified

=cut

sub get_default_directory {
    my ( $theme, $subdir, $app ) = @_;
    $theme  ||= '';
    $subdir ||= '';
    my $docroot = ( $app && $app eq 'webmail' ) ? '/usr/local/cpanel/base/webmail' : '/usr/local/cpanel/base/frontend';
    return $docroot . "/${theme}${subdir}";
}

1;
