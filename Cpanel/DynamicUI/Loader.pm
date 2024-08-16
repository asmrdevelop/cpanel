package Cpanel::DynamicUI::Loader;

# cpanel - Cpanel/DynamicUI/Loader.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use constant _ENOENT => 2;

use Cpanel::DynamicUI::Filter                      ();
use Cpanel::DynamicUI::Parser                      ();
use Cpanel::Exception                              ();
use Cpanel::Integration::Files                     ();
use Cpanel::AdminBin::Serializer::FailOK           ();
use Cpanel::Locale                                 ();
use Cpanel::Debug                                  ();
use Cpanel::LoadModule                             ();
use Cpanel::StatCache                              ();
use Cpanel::Themes::Utils                          ();
use Cpanel::Validate::FilesystemNodeName           ();
use Cpanel::FileUtils::Read::DirectoryNodeIterator ();    # PPI USE OK -- Needed for _get_dynamicui_cache_file_path_for_user
use Cpanel::JSON                                   ();
use Try::Tiny;

=head1 DESCRIPTION

Functions to load and parse the dynamicui.conf files

=cut

=head1 SYNOPSIS

    use Cpanel::DynamicUI::Loader;

     load_all_dynamicui_confs
        Loads all dynamicui.conf files for a user into a hashref

     list_dynamicui_confs_for_user_theme_brandingpkg
        Fetch a list of all dynamicui.conf for a user

=head1 FUNCTIONS

=cut

our $VERSION = '5.0';
my $locale;
my @REMOVED_FEATURES = ('frontpage');

=head2 load_all_dynamicui_confs

=head3 Purpose

Loads all the dynamicui.conf files for a user into a single hashref

=head3 Arguments

=head4 Required

=over

=item 'theme': string - The name of the cPanel theme

=item 'user': string - The name of the cPanel user (system user)

=item 'homedir': string - The home directory for the cPanel user (this is used to avoid a getpwnam call)

=item 'ownerhomedir': string - The home directory for the cPanel user's owner (this is used to avoid a getpwnam call)

=back

=head4 Optional

=over

=item 'need_description': boolean - If true, the description field will be included in the 'conf' output

=item 'showdeleted': boolean - If true, items which have been removed by cascaing loads of secondary dynamicui.conf will not be removed from the 'conf' output

=item 'need_origin': boolen - If true, the origin field will be included in the 'conf' output

=item 'nocache': boolean - If true, the cache will not be updated

=item 'dui_conf_files': opaque - cached result from get_dynamicui_conf_and_cache_files

=item 'dui_cache_file': opaque - cached result from get_dynamicui_conf_and_cache_files

=item 'mtime_dui_cache_must_beat_to_be_valid': opaque - cached result from get_dynamicui_conf_and_cache_files

=back

=head3 Returns

=over

=item A hashref that has the following structure.

=over

=item 'conf': hashref - A combined dynamicui conf structure

=item 'dyalist': arrayref - A list of each dynamicui.conf along with its description

=item 'cachetime': integer - The time to use for caching (the time that this data was gathered)

=item 'version': string - The version of this module

=back

=back

If an error occurs, the function will throw an exception.

=cut

sub load_all_dynamicui_confs {
    my %OPTS = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'user' ] ) if !$OPTS{'user'};

    my $privs_obj = _drop_privs_if_needed( $OPTS{'user'} );

    if ( !$OPTS{'dui_conf_files'} ) {
        my $conf_cache_mtime_ref = get_dynamicui_conf_and_cache_files(%OPTS);
        @OPTS{ keys %$conf_cache_mtime_ref } = values %$conf_cache_mtime_ref;    # dui_conf_files, dui_cache_file, mtime_dui_cache_must_beat_to_be_valid
    }

    return _load_all_dynamicui_confs_from_dui_conf_and_cache(%OPTS);
}

sub _load_all_dynamicui_confs_from_dui_conf_and_cache {
    my (%OPTS) = @_;

    foreach my $required (qw(user dui_conf_files dui_cache_file theme mtime_dui_cache_must_beat_to_be_valid)) {
        die Cpanel::Exception::create( 'MissingParameter', [ 'name' => $required ] ) if !$OPTS{$required};
    }

    my ( $user, $dui_conf_files, $dui_cache_file, $theme, $mtime_dui_cache_must_beat_to_be_valid ) = @OPTS{ 'user', 'dui_conf_files', 'dui_cache_file', 'theme', 'mtime_dui_cache_must_beat_to_be_valid' };

    if ($dui_cache_file) {
        my $cached_dui_result;
        try {
            $cached_dui_result = _load_dui_from_cache_if_valid(
                'dui_conf_files'                        => $dui_conf_files,
                'dui_cache_file'                        => $dui_cache_file,
                'mtime_dui_cache_must_beat_to_be_valid' => $mtime_dui_cache_must_beat_to_be_valid,
            );
        }
        catch {
            Cpanel::Debug::log_warn("$_");
        };
        return $cached_dui_result if $cached_dui_result;

    }
    my $combined_dui_conf = _load_dynamicui_confs_into_hashref(
        $dui_conf_files,
        {
            'need_description' => $OPTS{'need_description'},
            'showdeleted'      => $OPTS{'showdeleted'},
            'need_origin'      => $OPTS{'need_origin'}
        }
    );

    my $result = { 'conf' => $combined_dui_conf, 'dyalist' => $dui_conf_files, 'cachetime' => time(), 'version' => $VERSION };

    if ( !$OPTS{'nocache'} && !$OPTS{'showdeleted'} ) {
        try {
            require Cpanel::FileUtils::Write;
            Cpanel::FileUtils::Write::overwrite( $dui_cache_file, Cpanel::JSON::Dump($result), 0640 );
        }
        catch {
            Cpanel::Debug::log_warn( Cpanel::Exception::get_string($_) );
        };
    }
    return $result;
}

=head2 get_dynamicui_conf_and_cache_files

=head3 Purpose

Reduce a list of dynamicui config files that the account
uses along with their caches and the mtime needed for the cache
to be valid

=head3 Arguments

=head4 Required

=over

=item 'theme': string - The name of the cPanel theme

=item 'user': string - The name of the cPanel user (system user)

=item 'homedir': string - The home directory for the cPanel user (this is used to avoid a getpwnam call)

=item 'ownerhomedir': string - The home directory for the cPanel user's owner (this is used to avoid a getpwnam call)

=back

=head4 Optional

=over

=item 'need_origin': boolean - Include the origin in the return

=back


=head3 Returns

=over

=item A hashref in the following format.

  Sample:
   {
            'mtime_dui_cache_must_beat_to_be_valid' => 1471203368,
            'dui_cache_file' => '/usr/local/cpanel/t/tmp/homedir_base.9PGj8/ex7vqo56/.cpanel/caches/dynamicui/paper_lantern_en_.cache',
            'dui_conf_files' => [
                                  {
                                    'allow_legacy' => 1,
                                    'file' => '/usr/local/cpanel/base/frontend/jupiter/dynamicui.conf'
                                  },
                                ...
            ]
   }

=over

=item 'dui_conf_files': arrayref - hashrefs of dynamicui.conf files path and allow_legacy setting

=item 'dui_cache_file': string - The cache file continaing the cachable dyanmicui.conf files

=item 'mtime_dui_cache_must_beat_to_be_valid': int - The mtime that the cache file must exceed in order to be valid

=back

=back

If an error occurs, the function will throw an exception.

=cut

sub get_dynamicui_conf_and_cache_files {
    my %OPTS = @_;
    foreach my $required (qw(theme user homedir ownerhomedir)) {
        die Cpanel::Exception::create( 'MissingParameter', [ 'name' => $required ] ) if !$OPTS{$required};
    }

    foreach my $path_safe (qw(theme user)) {
        Cpanel::Validate::FilesystemNodeName::validate_or_die( $OPTS{$path_safe} );
    }
    Cpanel::Validate::FilesystemNodeName::validate_or_die( $OPTS{'brandingpkg'} ) if length $OPTS{'brandingpkg'};

    my ( $user, $user_homedir, $theme, $ownerhomedir, $brandingpkg ) = @OPTS{ 'user', 'homedir', 'theme', 'ownerhomedir', 'brandingpkg' };
    $brandingpkg ||= '';

    my $privs_obj = _drop_privs_if_needed($user);

    my $dui_conf_files = list_dynamicui_confs_for_user_theme_brandingpkg(
        'theme'        => $theme,
        'brandingpkg'  => $brandingpkg,
        'user'         => $user,
        'ownerhomedir' => $ownerhomedir,
        'need_origin'  => $OPTS{'need_origin'}
    );

    my $dui_cache_file;
    my $mtime_dui_cache_must_beat_to_be_valid;
    try {
        $dui_cache_file = _get_dynamicui_cache_file_path_for_user(
            'user_homedir' => $user_homedir,
            'theme'        => $theme,
            'user_locale'  => _locale()->language_tag(),
            'brandingpkg'  => $brandingpkg
        );

        $mtime_dui_cache_must_beat_to_be_valid = get_mtime_that_dui_cache_must_beat_to_be_considered_valid(
            'dui_conf_files' => $dui_conf_files,
            'dui_cache_file' => $dui_cache_file,
            'theme'          => $theme,
        );
    }
    catch {
        Cpanel::Debug::log_warn("$_");
    };
    return {
        'dui_conf_files'                        => $dui_conf_files,
        'dui_cache_file'                        => $dui_cache_file,
        'mtime_dui_cache_must_beat_to_be_valid' => $mtime_dui_cache_must_beat_to_be_valid
    };
}

=head2 list_dynamicui_confs_for_user_theme_brandingpkg

=head3 Purpose

Fetch a list of all the dynamicui.conf files for a user

=head3 Arguments

=head4 Required

=over

=item 'theme': string - The name of the cPanel theme

=item 'user': string - The name of the cPanel user (system user)

=item 'ownerhomedir': string - The home directory for the cPanel user's owner (this is used to avoid a getpwnam call)

=back

=head4 Optional

=over

=item 'need_origin': boolean - Include the origin in the return

=back


=head3 Returns

=over

=item An arrayref that has multiple instances of following hashref.

=over

=item 'file': string - The path to the dynamicui.conf file

=item 'origin': string - The origin of the dynamicui.conf in human readable terms

=back

=back

If an error occurs, the function will throw an exception.

=cut

sub list_dynamicui_confs_for_user_theme_brandingpkg {
    my (%OPTS) = @_;

    foreach my $required (qw(theme user ownerhomedir)) {
        die Cpanel::Exception::create( 'MissingParameter', [ 'name' => $required ] ) if !$OPTS{$required};
    }

    my ( $user, $theme, $ownerhomedir, $brandingpkg ) = @OPTS{ 'user', 'theme', 'ownerhomedir', 'brandingpkg' };
    my $privs_obj = _drop_privs_if_needed($user);
    $brandingpkg ||= '';
    my $need_origin = $OPTS{'need_origin'};
    _locale() if $need_origin;

    my $theme_root = Cpanel::Themes::Utils::get_theme_root($theme);
    my @DYALIST    = (
        {

            file => "$theme_root/dynamicui.conf",
            ( $need_origin ? ( origin => "$theme (" . $locale->maketext('System') . ')' ) : () ),
            allow_legacy => 1,
        }
    );

    local $!;
    if ( opendir my $add_fh, "$theme_root/dynamicui" ) {
        foreach my $potential_dynamicui_file ( grep { index( $_, 'dynamicui' ) > -1 } readdir($add_fh) ) {
            push(
                @DYALIST,
                {
                    file => "$theme_root/dynamicui/$potential_dynamicui_file",
                    ( $need_origin ? ( origin => "$theme plugin $potential_dynamicui_file (" . $locale->maketext('System') . ')' ) : () ),
                    allow_legacy => 1,
                }
            );
        }
        closedir $add_fh;
    }
    elsif ( $! != _ENOENT() ) {
        Cpanel::Debug::log_warn("Failed to open: $theme_root/dynamicui: $!");
    }

    push @DYALIST,
      {
        file => "$ownerhomedir/cpanelbranding/$theme/dynamicui.conf",
        ( $need_origin ? ( origin => "$theme [root] (" . $locale->maketext('Yours') . ')' ) : () ),
        allow_legacy => 1,
      };
    if ($brandingpkg) {
        push @DYALIST, {

            'file' => "$theme_root/branding/$brandingpkg/dynamicui.conf",
            ( $need_origin ? ( 'origin' => "$theme [$brandingpkg] (" . $locale->maketext('System') . ')' ) : () ),
            allow_legacy => 1,
        };
        push @DYALIST, {

            'file' => "$ownerhomedir/cpanelbranding/$theme/$brandingpkg/dynamicui.conf",
            ( $need_origin ? ( 'origin' => "$theme [$brandingpkg] (" . $locale->maketext('Yours') . ')' ) : () ),
            allow_legacy => 1,
        };
    }

    push @DYALIST, map {
        {
            file => $_,
            ( $need_origin ? ( origin => "Integration (" . $locale->maketext('System') . ')' ) : () ),
            allow_legacy => 0
        },
    } Cpanel::Integration::Files::get_dynamicui_files_for_user($user);

    return \@DYALIST;
}

sub _get_dynamicui_cache_file_path_for_user {
    my (%OPTS) = @_;

    foreach my $required (qw(user_homedir theme user_locale)) {
        die Cpanel::Exception::create( 'MissingParameter', [ 'name' => $required ] ) if !$OPTS{$required};
    }

    my ( $user_homedir, $user_locale, $theme, $brandingpkg ) = @OPTS{ 'user_homedir', 'user_locale', 'theme', 'brandingpkg' };
    $brandingpkg ||= '';
    my $cache_dir;

    if ( !$ENV{'TEAM_USER'} ) {
        $cache_dir = "$user_homedir/.cpanel/caches/dynamicui";
    }
    else {
        $cache_dir = "$user_homedir/$ENV{'TEAM_USER'}/.cpanel/caches/dynamicui";
    }

    if ( !Cpanel::StatCache::cachedmtime($cache_dir) ) {
        local $!;    # no autodie for safemkdir yet
                     # This code may be executed as root via bin/rebuild_sprites
                     # Do not die here as they won't be able to load cpanel if over quota
        require Cpanel::SafeDir::MK;
        Cpanel::SafeDir::MK::safemkdir( $cache_dir, 0700 ) or Cpanel::Debug::log_warn( Cpanel::Exception::create( 'IO::DirectoryCreateError', [ path => $cache_dir, error => $! ] ) );

    }

    return "$cache_dir/${theme}_${user_locale}_${brandingpkg}.cache";
}

sub get_mtime_that_dui_cache_must_beat_to_be_considered_valid {
    my (%OPTS) = @_;

    foreach my $required (qw(dui_conf_files dui_cache_file theme)) {
        die Cpanel::Exception::create( 'MissingParameter', [ 'name' => $required ] ) if !$OPTS{$required};
    }

    my ( $dui_conf_files, $dui_cache_file, $theme ) = @OPTS{ 'dui_conf_files', 'dui_cache_file', 'theme' };

    return time() + 1 if $OPTS{'showdeleted'} || $OPTS{'nocache'};

    my $newest_conf_mtime = Cpanel::StatCache::cachedmtime( _locale()->get_cdb_file_path() ) || 0;
    my $mtime;
    foreach my $dobj ( @$dui_conf_files, Cpanel::Themes::Utils::get_theme_root($theme) . "/dynamicui" ) {
        next if !( $mtime = Cpanel::StatCache::cachedmtime( ref $dobj ? $dobj->{'file'} : $dobj ) );
        if ( $mtime > $newest_conf_mtime ) { $newest_conf_mtime = $mtime; }
    }

    # If the features change in the cpanel users file then the cache is invalid as well
    if ( $Cpanel::CPDATA{'MTIME'} && $Cpanel::CPDATA{'MTIME'} > $newest_conf_mtime ) {
        $newest_conf_mtime = $Cpanel::CPDATA{'MTIME'};
    }

    return $newest_conf_mtime;
}

sub _load_dui_from_cache_if_valid {
    my (%OPTS) = @_;

    foreach my $required (qw(dui_cache_file dui_conf_files mtime_dui_cache_must_beat_to_be_valid)) {
        die Cpanel::Exception::create( 'MissingParameter', [ 'name' => $required ] ) if !$OPTS{$required};
    }

    my ( $dui_cache_file, $dui_conf_files, $mtime_dui_cache_must_beat_to_be_valid ) = @OPTS{ 'dui_cache_file', 'dui_conf_files', 'mtime_dui_cache_must_beat_to_be_valid' };
    my $cache_mtime = Cpanel::StatCache::cachedmtime($dui_cache_file);
    Cpanel::LoadModule::load_perl_module('Cpanel::Team::Config');
    my $team_cache_file_mtime = Cpanel::Team::Config::get_mtime_team_config( $ENV{'TEAM_USER'}, $ENV{'TEAM_OWNER'} );

    if ( $cache_mtime > $mtime_dui_cache_must_beat_to_be_valid ) {
        my $dui_cache_ref = Cpanel::AdminBin::Serializer::FailOK::LoadFile($dui_cache_file);
        if ( $dui_cache_ref && scalar keys %{$dui_cache_ref} ) {
            if ( $dui_cache_ref->{'conf'} && $dui_cache_ref->{'cachetime'} > $mtime_dui_cache_must_beat_to_be_valid && $dui_cache_ref->{'version'} == $VERSION && _dyalist_matches( $dui_conf_files, $dui_cache_ref->{'dyalist'} ) && $dui_cache_ref->{'cachetime'} > $team_cache_file_mtime ) {
                return $dui_cache_ref;
            }
        }
    }

    return undef;
}

sub _load_dynamicui_confs_into_hashref {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my ( $dui_conf_files, $opts_ref ) = @_;

    my %DYNAMIC_UI_CONF;

    # Remove features from the list when we load as its much faster than
    # trying to clean them out later
    my $removed_feature_regex_text = q{feature=>(?:} . join( '|', map { quotemeta($_) } @REMOVED_FEATURES ) . ')';
    my $removed_feature_regex      = qr{$removed_feature_regex_text};
    #
    my $dynui_data;

    Cpanel::LoadModule::load_perl_module('Cpanel::Locale');

    #This is get_non_singleton_handle(), not get_handle(), so that we can set a context
    #on this object without affecting other locale objects.
    my $locale = Cpanel::Locale->get_non_singleton_handle();
    $locale->set_context('html');

    foreach my $dobj (@$dui_conf_files) {
        my ( $dyna, $origin, $allow_legacy ) = @{$dobj}{qw( file  origin  allow_legacy )};

        if ( !Cpanel::StatCache::cachedmtime($dyna) ) {
            next;
        }
        elsif ( !-r $dyna ) {
            Cpanel::Debug::log_warn("Failed to read: $dyna: $!");
            next;
        }

        if ($allow_legacy) {
            $dynui_data = Cpanel::DynamicUI::Parser::read_dynamicui_file_allow_legacy($dyna);
        }
        else {
            $dynui_data = Cpanel::DynamicUI::Parser::read_dynamicui_file($dyna);
        }

        next if $#$dynui_data == -1;

        for my $cur_entry (@$dynui_data) {
            delete $cur_entry->{'description'} if !$opts_ref->{'need_description'};

            $cur_entry->{'skipobj'} = 1 unless Cpanel::DynamicUI::Filter::is_valid_entry($cur_entry);

            if ( $cur_entry->{'skipobj'} ) {
                if ( $opts_ref->{'showdeleted'} ) {
                    $DYNAMIC_UI_CONF{ $cur_entry->{'file'} }->{'deleted'} = 1;
                }
                else {
                    delete $DYNAMIC_UI_CONF{ $cur_entry->{'file'} };
                }
            }
            else {
                $DYNAMIC_UI_CONF{ $cur_entry->{'file'} } = $cur_entry;
                foreach my $key ( keys %{$cur_entry} ) {
                    my $value = $cur_entry->{$key};
                    if ( length $value && $value =~ m{\$LANG\{'?([^'\}]+)'?\}} ) {
                        if ( $key eq 'searchtext' ) {

                            # We want to evaluate the search keywords in plain context
                            # as we dont want to have html entities polluting the search
                            # keywords
                            $locale->set_context('plain');
                            $cur_entry->{$key} = $locale->makevar($1);
                            $locale->set_context('html');
                            next;
                        }
                        elsif ( $key eq 'itemdesc' ) {
                            $cur_entry->{'plainitemdesc'} = $1;
                        }
                        $cur_entry->{$key} = $locale->makevar($1);
                    }
                }

                if ( $opts_ref->{'need_origin'} ) {
                    $cur_entry->{'origin'} = $origin;
                }
                if ( !length $cur_entry->{'target'} ) {
                    if ( length $cur_entry->{'acontent'} && $cur_entry->{'acontent'} =~ m{target=\"([^"]+)} ) {    #optimization for paper_lantern
                        $cur_entry->{'target'} = $1;
                    }
                    else {
                        $cur_entry->{'target'} = '';                                                               # all items need a target
                    }
                }
                $cur_entry->{'acontent'}         ||= ( $cur_entry->{'target'} ? ( 'target="' . $cur_entry->{'target'} . '"' ) : '' );    # all items need an acontent
                $cur_entry->{'onclick'}          ||= '';                                                                                 # all items need an onclick
                $cur_entry->{'base64_png_image'} ||= '';                                                                                 # all items need an empty base64_png_image is non-existent
                $cur_entry->{'itemdesc'}         ||= $cur_entry->{'file'};                                                               # all items need an itemdesc
                if ( length $cur_entry->{'searchtext'} ) {
                    if ( index( $cur_entry->{'searchtext'}, $cur_entry->{'itemdesc'} ) == -1 ) {
                        $cur_entry->{'searchtext'} .= " " . $cur_entry->{'itemdesc'};
                    }
                }
                else {
                    $cur_entry->{'searchtext'} = $cur_entry->{'itemdesc'};
                }
            }
        }

    }
    return \%DYNAMIC_UI_CONF;
}

sub _dyalist_matches {
    my ( $a1, $a2 ) = @_;

    return 0 if scalar @{$a1} != scalar @{$a2};
    return 1 if join( '_', sort map { $_->{'file'} } @{$a1} ) eq join( '_', sort map { $_->{'file'} } @{$a2} );
    return 0;

}

sub _locale {
    Cpanel::LoadModule::load_perl_module('Cpanel::Locale') if !$INC{'Cpanel/Locale.pm'};
    return ( $locale ||= Cpanel::Locale::lh() );
}

sub _drop_privs_if_needed {
    my ($user) = @_;
    if ( $> == 0 && $user ne 'root' ) {
        require Cpanel::AccessIds::ReducedPrivileges;
        return Cpanel::AccessIds::ReducedPrivileges->new($user);
    }
    return;
}

1;
