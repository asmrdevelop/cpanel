package Whostmgr::Theme;

# cpanel - Whostmgr/Theme.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Whostmgr::Theme - Module containing functions controlling the WHM themes

=head1 SYNOPSIS

    use Whostmgr::Theme;

    Whostmgr::settheme();
    Whostmgr::gettheme();

=head1 DESCRIPTION

Module containing functions controlling the WHM themes. In this module you
can specify a reseller or root theme and get other information about the themes.

=cut

use strict;
use warnings;

use Cpanel::StatCache        ();
use Cpanel::LoadFile         ();
use Cpanel::LoadModule       ();
use Cpanel::Debug            ();
use Cpanel::StringFunc::Trim ();

our $ROOT_THEME_FILE = '/root/.whmtheme';
our $DEFAULT_THEME   = 'x';
our $THEME_BASE      = '/usr/local/cpanel/whostmgr/docroot/themes';

our $DEFAULT_FALLBACK_DIR = '/usr/local/cpanel/whostmgr/docroot';

my @FORBIDDEN_THEMES = qw(
  gorgo
  bluetruee
  blue
  black
  orange
);
my %FORBIDDEN_THEMES = map { $_ => 1 } @FORBIDDEN_THEMES;

our $_Cached_Theme;

sub _get_fallback_theme_if_needed {
    my ($theme) = @_;

    if (   !$theme
        || index( $theme, '.' ) == 0
        || $FORBIDDEN_THEMES{$theme}
        || !_is_theme_on_disk($theme) ) {
        $theme = $DEFAULT_THEME;
    }

    return $theme;
}

=head2 set_reseller_theme

Set the WHM theme of the supplied reseller.

=over 2

=item Input

=over 3

=item C<SCALAR>

    $reseller - The username of the reseller to set the WHM theme for.

=back

=over 3

=item C<SCALAR>

    $new_theme - The folder name of the theme you would like to use

=back

=item Output

=over 3

=item C<SCALAR>

    If the reseller provided is 'root', this function returns 1 or dies.

    Otherwise, this returns the result of the C<Cpanel::Config::CpUserGuard::save>.

=back

=back

=cut

sub set_reseller_theme {
    my ( $reseller, $new_theme ) = @_;

    # No point in setting an invalid theme
    # and this check prevents bad data being set in the user file
    $new_theme = _get_fallback_theme_if_needed($new_theme);

    # Root is a special case as it doesn't have a CpUser file
    if ( $reseller eq 'root' ) {

        # This is hard coded so we don't have to use the PwCache to figure it out.
        Cpanel::LoadModule::load_perl_module('Cpanel::FileUtils::Write');
        Cpanel::FileUtils::Write::overwrite( $ROOT_THEME_FILE, $new_theme, 0600 );

        return 1;
    }
    else {
        Cpanel::LoadModule::load_perl_module('Cpanel::Config::CpUserGuard');

        my $cpuser_guard = Cpanel::Config::CpUserGuard->new($reseller);

        $cpuser_guard->{'data'}{'WHM_SELECTED_THEME'} = $new_theme;

        return $cpuser_guard->save();
    }

}

=head2 settheme

Set the theme of the current user, as defined by $ENV{'REMOTE_USER'}
This defaults to root if no $ENV{'REMOTE_USER'} is

=over 2

=item Input

=over 3

=item C<SCALAR>

    $new_theme - The folder name of the theme you would like to use

=back

=item Output

=over 3

=item C<SCALAR>

    Returns the result of the Cpanel::Config::CpUserGuard->save();

=back

=back

=cut

sub settheme {
    my ($new_theme) = @_;
    my $reseller = $ENV{'REMOTE_USER'} || 'root';

    $new_theme = _get_fallback_theme_if_needed($new_theme);

    my $result = set_reseller_theme( $reseller, $new_theme );

    # If successfully set, update cache to ensure latest and greatest
    $_Cached_Theme = $new_theme if $result;

    return $result;
}

sub _get_reseller_theme {
    my ($reseller) = @_;

    my $loaded_theme;
    my $theme;

    if ( $reseller eq 'root' ) {

        # reseller is root, and root file exists, load it
        $loaded_theme = Cpanel::LoadFile::load($ROOT_THEME_FILE) if -f $ROOT_THEME_FILE;
    }
    else {
        # Attempt to obtain from reseller Cpanel::Config::LoadCpUserFile
        Cpanel::LoadModule::load_perl_module('Cpanel::Config::LoadCpUserFile::CurrentUser');
        $loaded_theme = Cpanel::Config::LoadCpUserFile::CurrentUser::load($reseller)->{'WHM_SELECTED_THEME'} || undef;
    }

    if ( !$loaded_theme ) {
        my $whm_theme_file = '/var/cpanel/whmtheme';

        # theme hasn't previously been set, and whm_theme_file exists so use the set default
        $loaded_theme = Cpanel::LoadFile::load($whm_theme_file) if -f $whm_theme_file;
    }

    # still no theme, but we loaded one from a file (root or whm)
    if ( is_theme_name_valid($loaded_theme) ) {
        $theme = Cpanel::StringFunc::Trim::ws_trim($loaded_theme);
    }

    $theme = _get_fallback_theme_if_needed($theme);

    return $theme;
}

=head2 gettheme

Get the current default theme

=over 2

=item Output

=over 3

=item C<SCALAR>

    The folder name of the default theme

=back

=back

=cut

sub gettheme {
    return $DEFAULT_THEME;
}

=head2 getthemedir

Obtain the full path of the directory based on the theme passed or the users
current theme if no theme parameter is provided.

=over 2

=item Input

=over 3

=item C<SCALAR>

    $theme - Optional parameter to define which theme to get the dir for.
    If none is provided, the results of gettheme() will be used

=back

=item Output

=over 3

=item C<SCALAR>

    Returns the directory of the theme based on the $theme parameter provided.

=back

=back

=cut

sub getthemedir {
    my ($given_theme) = @_;

    return $THEME_BASE . '/' . ( $given_theme || gettheme() );
}

my @_Search_Paths;
my @_Search_Themes;

sub _get_search_paths {
    my ( $force, $return_themes_instead ) = @_;

    if ( !$force ) {
        return @_Search_Paths if @_Search_Paths;
    }

    if ( !@_Search_Paths || $force ) {
        my $current_theme = Whostmgr::Theme::gettheme();
        if ( $current_theme eq $DEFAULT_THEME ) {
            @_Search_Paths = (
                Whostmgr::Theme::getthemedir(),
                $DEFAULT_FALLBACK_DIR,
            );
            @_Search_Themes = ( $DEFAULT_THEME, q{} );
        }
        else {
            @_Search_Paths = (
                Whostmgr::Theme::getthemedir(),
                Whostmgr::Theme::getthemedir($DEFAULT_THEME),
                $DEFAULT_FALLBACK_DIR,
            );
            @_Search_Themes = ( $current_theme, $DEFAULT_THEME, q{} );
        }
    }

    return $return_themes_instead ? @_Search_Themes : @_Search_Paths;
}

my %_File_Paths;

=head2 find_file_path

Used to find a file path of a file based on the current theme selected

=over 2

=item Input

=over 3

=item C<SCALAR>

    $filename - File name and path you want to find within the theme

=back

=item Output

=over 3

=item C<SCALAR>

    Returns the found file, or nothing.

=back

=back

=cut

sub find_file_path {
    my ($filename) = @_;

    #defined is faster than exists or simple boolean
    return $_File_Paths{$filename} if defined $_File_Paths{$filename};

    if ( !@_Search_Paths ) {
        _get_search_paths();
    }

    my $found_file;
    for my $cur_dir (@_Search_Paths) {
        my $cur_file = $cur_dir . '/' . $filename;
        if ( Cpanel::StatCache::cachedmtime($cur_file) ) {
            $found_file = $cur_file;
            last;
        }
    }

    if ( defined $found_file ) {
        return $_File_Paths{$filename} = $found_file;
    }
    else {
        return;
    }
}

my %_Cached_themes;

=head2 get_themes_list

Returns a list of existing themes on the filesystem

=over 2

=item Output

=over 3

=item C<ARRAYREF>

    Returns a list of existing themes on the file system.

=back

=back

=cut

sub get_themes_list {

    return keys %_Cached_themes if %_Cached_themes;

    %_Cached_themes = _get_themes_list();

    return keys %_Cached_themes;
}

=head2 set_account_default_theme

Set default theme for new accounts.

=over 2

=item Input

=over 3

=item C<SCALAR>

    $theme - Name of the theme for account default

=back

=back

=cut

sub set_account_default_theme {
    my ($theme) = @_;
    return unless is_theme_name_valid($theme);

    Cpanel::LoadModule::load_perl_module('Cpanel::Config::LoadWwwAcctConf');
    Cpanel::LoadModule::load_perl_module('Cpanel::Config::SaveWwwAcctConf');

    my $wwwacct_ref = Cpanel::Config::LoadWwwAcctConf::loadwwwacctconf();
    return unless $wwwacct_ref;

    $wwwacct_ref->{'DEFMOD'} = $theme;
    return Cpanel::Config::SaveWwwAcctConf::savewwwacctconf($wwwacct_ref);
}

=head2 is_theme_name_valid

Validates a theme name for in setting a reseller's theme

=over 2

=item Input

=over 3

=item C<SCALAR>

    $theme - name of theme to validate

=back

=item Output

=over 3

=item C<SCALAR>

    Returns boolean based on whether theme name is valid

=back

=back

=cut

sub is_theme_name_valid {
    my ($theme) = @_;

    return if !length $theme;
    return if $theme =~ tr{/}{};
    return if index( $theme, '..' ) > -1;
    return if $theme =~ tr{\0}{};

    return 1;

}

# broken out for testing purposes for caching
sub _get_themes_list {

    my %themes;

    if ( opendir my $themes_dh, $THEME_BASE ) {
        my @files = readdir $themes_dh;
        closedir $themes_dh;
        foreach my $theme (@files) {
            if ( !$theme ) {
                Cpanel::Debug::log_warn('Bad theme directory lookup (possible rootkit installed)');
            }
            elsif ($theme !~ m{\A\.}
                && !( grep { $_ eq $theme } @FORBIDDEN_THEMES )
                && -d $THEME_BASE . '/' . $theme ) {
                $themes{$theme} = 1;
            }
        }
    }
    else {
        warn "Unable to open directory $THEME_BASE: $!";
    }

    return %themes;

}

sub _is_theme_on_disk {
    my ( $theme, $force_disk ) = @_;

    return if !$theme;

    if ( %_Cached_themes && !$force_disk ) {
        return $_Cached_themes{$theme} || 0;
    }
    else {
        return -d ( $THEME_BASE . '/' . $theme ) && -e _ ? 1 : 0;    # No need to do -r (costs 5 additional syscalls) since running as root
    }
}

1;
