package Cpanel::Locale::Utils::Files;

#                                      Copyright 2024 WebPros International, LLC
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited.

use strict;
use warnings;

use Cpanel::LoadFile             ();
use Cpanel::Locale::Utils::Paths ();
use Cpanel::Locale::Utils::Queue ();
use Cpanel::Server::Type         ();

sub get_file_list {
    my ( $tag, $theme, $include_cdb ) = @_;

    return if !$tag || !$theme;

    my $locale_database_root = Cpanel::Locale::Utils::Paths::get_locale_database_root();
    my $locale_yaml_root     = Cpanel::Locale::Utils::Paths::get_locale_yaml_root();

    my @files;
    if ( $theme eq '/' ) {

        @files = (
            Cpanel::Locale::Utils::Paths::get_locale_yaml_root() . "/$tag.yaml",
            Cpanel::Locale::Utils::Paths::get_locale_yaml_local_root() . "/$tag.yaml",
            get_plugin_files($tag),
            get_addon_files($tag),
            get_legacy_files( $tag, Cpanel::Locale::Utils::Paths::get_legacy_lang_root() ),
            "$locale_database_root/3rdparty/conf/$tag",
            "/usr/local/cpanel/Cpanel/Locale/$tag.pm",
            Cpanel::Locale::Utils::Queue::get_pending_file_list_for_locale($tag),
            $include_cdb             ? "$locale_database_root/$tag.cdb"                                         : (),
            index( $tag, 'i_' ) == 0 ? Cpanel::Locale::Utils::Paths::get_i_locales_config_path() . "/$tag.yaml" : (),
        );

        push @files, "$locale_yaml_root/queue/pending.yaml" if $tag eq 'en';
    }
    else {
        my $theme_root = "/usr/local/cpanel/base/frontend/$theme";

        @files = ( "$theme_root/locale/$tag.yaml", "$theme_root/locale/$tag.yaml.local", get_legacy_files( $tag, "$theme_root/lang" ), $include_cdb ? "$locale_database_root/themes/$theme/$tag.cdb" : (), );

        # no .pm, i_ config removal, no addon files, no 3rdparty conf
    }

    return @files;
}

sub get_legacy_files {
    my ( $tag, $path ) = @_;

    my @legacy_files;
    require Cpanel::Locale::Utils::Legacy;
    for my $legacy ( Cpanel::Locale::Utils::Legacy::get_existing_filesys_legacy_name_list( 'no_root' => 1, 'also_look_in' => [$path] ) ) {
        next if $legacy =~ m/\.local$/;
        next if Cpanel::Locale::Utils::Legacy::get_new_langtag_of_old_style_langname($legacy) ne $tag;
        push @legacy_files, "$path/$legacy", "$path/$legacy.local";
    }
    return @legacy_files;
}

sub get_addon_files {
    my ($tag) = @_;

    require Cpanel::SafeDir::Read;
    my @addon_paths = map { -d "/usr/local/cpanel/modules-install/$_" ? "/usr/local/cpanel/modules-install/$_" : () } Cpanel::SafeDir::Read::read_dir('/usr/local/cpanel/modules-install/');

    my @addon_files;
    for my $path (@addon_paths) {
        push @addon_files, ( "$path/locale/$tag.yaml", get_legacy_files( $tag, "$path/lang" ) );
    }
    return @addon_files;
}

sub get_plugin_files {
    my ($tag) = @_;

    require Cpanel::SafeDir::Read;
    my @plugin_paths = map { -d "/var/cpanel/plugins/$_" ? "/var/cpanel/plugins/$_" : () } Cpanel::SafeDir::Read::read_dir('/var/cpanel/plugins/');

    my @plugin_files;
    for my $path (@plugin_paths) {
        push @plugin_files, ("$path/locale/$tag.yaml");
    }
    return @plugin_files;
}

my $_js_files_list_path_contents;

sub _clear_get_js_files_list_path_contents {
    undef $_js_files_list_path_contents;
    return;
}

sub _get_js_files_list_path_contents {
    require Cpanel::LoadFile;
    return ( $_js_files_list_path_contents ||= _load_js_files_list() || [] );
}

sub _load_js_files_list {
    my $buildin_files = Cpanel::LoadFile::loadfileasarrayref( _get_js_files_list_path() ) || [];
    my $addon_files   = get_plugin_js_file_lists()                                        || [];
    return [ $buildin_files->@*, $addon_files->@* ];
}

sub get_plugin_js_file_lists {

    my @addon_js_files;
    require Cpanel::SafeRun::Dynamic;
    Cpanel::SafeRun::Dynamic::saferun_callback(
        'prog'     => [ 'find', '-L', '/var/cpanel/plugins', qw{-type f -name js_files_with_mt_calls} ],
        'callback' => sub {
            my ($file) = @_;
            chomp($file);
            my $paths = Cpanel::LoadFile::loadfileasarrayref($file);
            foreach my $path ( $paths->@* ) {
                push @addon_js_files, $path;
            }
        },
    );
    return \@addon_js_files;
}

sub get_js_files {
    my ($tag) = @_;

    my $deftheme = $Cpanel::Config::Constants::DEFAULT_CPANEL_THEME;

    $tag =~ s{[./]+}{}g;    # could use normalize_tag()

    my @js = map { substr( $_, 0, -3 ) . "-$tag.js" } map {
        chomp;
        get_js_variations($_)
    } @{ _get_js_files_list_path_contents() };

    if ( Cpanel::Server::Type::is_dnsonly() ) {
        @js = grep { $_ !~ qr{^/usr/local/cpanel/base/frontend/$deftheme/} } @js;
    }

    # Existence does not matter here so do not filter what is returned based on it.
    # The file name should end in -$tag.js for consistency and sanity of caller.
    return ( _get_root() . "/base/cjt/cpanel-all-min-$tag.js", _get_root() . "/base/cjt/cjt-min-$tag.js", @js );

}

my $lh;

sub clean_js_files {
    my ($conf) = @_;
    my $verbose = $conf->{'verbose'} || 0;

    if ( !$lh ) {
        require Cpanel::Locale;
        $lh = Cpanel::Locale->get_handle();
    }

    require Cpanel::LoadFile;
    chomp( my @mt_list = @{ Cpanel::LoadFile::loadfileasarrayref( _get_js_files_list_path() ) || [] } );

    # .prev is created during upcp on customer boxes
    # if we have one we need to build the .removed list based on it
    if ( -e _get_js_files_list_path() . ".prev" ) {
        my @removed;
        chomp( my @prev_list = @{ Cpanel::LoadFile::loadfileasarrayref( _get_js_files_list_path() . ".prev" ) || [] } );
        my %cur_list;
        @cur_list{@mt_list} = ();

        for my $prev (@prev_list) {
            push @removed, $prev if !exists $cur_list{$prev};
        }

        if ( _write_array_to_disk( _get_js_files_list_path() . '.removed', \@removed, { 'verbose' => $verbose, 'label' => 'removed' } ) ) {
            unlink( _get_js_files_list_path() . ".prev" ) or warn "Could not remove .prev file: $!\n";
        }
        else {
            warn "Could not update .removed list: $!";
        }
    }

    chomp( my @rm_list = @{ Cpanel::LoadFile::loadfileasarrayref( _get_js_files_list_path() . ".removed" ) || [] } );

    my %root;
    @root{ @rm_list, @mt_list } = ();

    # Add the removed file and every variation (-min, .min, _optimized) to the list for removal
    my @removed = map { chomp; get_js_variations($_) } @rm_list;
    my %avail;

    print "Checking for files to remove …\n" if $verbose;
    for my $tag ( 'en', 'en_us', 'i_default', $lh->list_available_locales() ) {
        $avail{$tag} = 1;
        next if $conf->{'only-unavailable-locales'};
        my @potentials = map {
            my $copy = $_;
            $copy =~ s/\.js$/-$tag.js/;
            $copy
        } @removed;

        # Do not include the original removed files here (in @removed) since these could be files generated outside of the locale system.
        for my $file ( @potentials, ( $conf->{'removed-only'} ? () : get_js_files( $tag, $verbose ) ) ) {
            if ( -e $file && !exists $root{$file} ) {    # root files are in the product, if they are removed that will be done via cpanelsync @ upcp (or equiv)
                print "Removing previously auto-generated “$file” …\n" if $verbose;
                unlink $file || warn "Could not clean “$file”: $!\n";
            }
        }
    }

    ## now deal with files for locales that were removed ##
    print "Checking for removed locale files …\n" if $verbose;
    my @potentials = map {
        my $copy = $_;
        $copy =~ s/\.js$/-.*.js/;
        $copy
    } @removed;
    for my $match ( @potentials, get_js_files( '.*', $verbose ) ) {
        for my $file ( glob($match) ) {
            if ( $file =~ m/\-([^-]+)\.js$/ ) {
                my $tag = $1;
                next if exists $avail{$tag};
                next if $tag eq 'min';

                print "Removing previously auto-generated “$file” …\n" if $verbose;
                unlink $file || warn "Could not clean “$file”: $!\n";
            }
        }
    }

    return;
}

sub dev_gen_js_files_list {
    my ($conf) = @_;
    my $verbose = $conf->{'verbose'} || 0;

    if ( !-e '/var/cpanel/dev_sandbox' ) {    # dev_sandbox file is present on build boxes
        warn "dev_gen_js_files_list() should only be executed on a sandbox or a build machine\n";
        return;
    }

    clean_js_files($conf) unless $conf->{'no_clean_locale_js'};

    #   1. get @files from git grep -l maketext -- '*.js' # JS has only maketext() which simplifies this greatly ## no extract maketext
    my @files;
    require Cpanel::SafeRun::Dynamic;
    print "Finding new files …\n" if $verbose;

    my $repo_root = _get_root();

    Cpanel::SafeRun::Dynamic::saferun_callback(
        'prog'     => [ qw(git grep -l --full-name maketext -- ), "$repo_root/*.js" ],    # JS has only maketext() which simplifies this greatly ## no extract maketext
        'callback' => sub {
            my ($line) = @_;
            chomp($line);
            push @files, "$repo_root/$line" if $line !~ m/.spec.js$/;
        },
    );

    #   2. only keep ones that have actual maketext() calls ## no extract maketext
    @files = grep { _file_has_mt_call($_) } @files;

    #   2.1. Include extra files that are composed or minified from other files.
    #   This happens after the actual call check because they haven't been
    #   created yet and would otherwise be excluded because they didn't exist.
    #   2.1 is not needed because we lookup the locale for js2-min in js2

    #   2.2. Include extra files that are composed or minified from other files using RequireJS or Stencil
    my $deftheme = $Cpanel::Config::Constants::DEFAULT_CPANEL_THEME || "jupiter";
    my $dirs     = [
        $repo_root . "/share/libraries/cjt2",
        $repo_root . "/share/apps",
        $repo_root . "/base/frontend/$deftheme",
        $repo_root . "/base/unprotected",
        $repo_root . "/base/webmail/$deftheme",
        $repo_root . "/whostmgr/docroot",
    ];

    for my $dir (@$dirs) {
        Cpanel::SafeRun::Dynamic::saferun_callback(
            'prog'     => [ qw/make -s -C/, $dir, 'list' ],
            'callback' => sub {
                my ($line) = @_;
                my $curr_dir = $dir;
                chomp($line);
                return if $line =~ /^make(\[\d+\])?:\s+/;    # No files
                my $curr_file = "$curr_dir/$line";
                push @files, $curr_file if !-d $curr_file && _file_has_mt_call($curr_file);
            },
        );
    }

    #  2.3 Include symlinked files since git grep can't find
    push @files, _get_symlinked_files(@$dirs);

    #   3. put them, one per line, in  _get_js_files_list_path()
    my $file = _get_js_files_list_path();

    #   3.1 but first recalc .removed
    require Cpanel::LoadFile;
    my @current = @{ Cpanel::LoadFile::loadfileasarrayref($file) || [] };
    chomp(@current);
    my %new;
    @new{@files} = ();
    my @removed;
    for my $cur (@current) {
        push @removed, $cur if !exists $new{$cur};
    }

    @files = sort @files;

    _write_array_to_disk( "$file.removed", \@removed, { 'verbose' => $verbose, 'label' => 'removed' } );
    _write_array_to_disk( $file,           \@files,   { 'verbose' => $verbose, 'label' => 'build' } );

    _clear_get_js_files_list_path_contents();

    return;
}

sub _get_symlinked_files {
    my (@dirs) = @_;
    my @files;
    require Cpanel::SafeRun::Dynamic;
    Cpanel::SafeRun::Dynamic::saferun_callback(
        'prog'     => [ 'find', @dirs, qw{-type l -name *.js} ],
        'callback' => sub {
            my ($link) = @_;
            chomp($link);
            push @files, $link if _file_has_mt_call($link);
        },
    );
    return @files;
}

sub _write_array_to_disk {
    my ( $file, $list_ar, $conf ) = @_;

    if ( open my $fh, '>', $file ) {
        for my $item ( @{$list_ar} ) {
            print "Adding “$item” to “$conf->{'label'}” list …\n" if $conf->{'verbose'};
            print {$fh} "$item\n";
        }
        close($fh);
    }
    else {
        warn "Could not open “$file” for writing: $!\n";
        return;
    }

    return 1;
}

sub get_js_variations {
    return if !defined $_[0] || $_[0] eq '';

    if (   substr( $_[0], -7 ) ne '.min.js'
        && substr( $_[0], -7 ) ne '-min.js'
        && substr( $_[0], -13 ) ne '_optimized.js' ) {
        return (
            substr( $_[0], 0, -3 ) . '-min.js',          #min
            substr( $_[0], 0, -3 ) . '.min.js',          #dot
            substr( $_[0], 0, -3 ) . '_optimized.js',    #opt
            $_[0]
        );
    }

    return $_[0];
}

# to be able to mock for testing
sub _get_js_files_list_path {
    return '/usr/local/cpanel/etc/.js_files_in_repo_with_mt_calls';
}

# to be able to mock for testing
sub _get_root {
    return '/usr/local/cpanel';    # TODO ? make repo agnostic ?: … -- $(git rev-parse --show-toplevel)
}

sub _file_has_mt_call {
    my ($file) = @_;

    my $text = Cpanel::LoadFile::load_if_exists($file) or return;

    #The keys we look for are:
    #
    #   - maketext (usual case)     ## no extract maketext
    #   - lextext                   ## no extract maketext
    #   - cptext (legacy)           ## no extract maketext
    #   - translatable              ## no extract maketext
    #
    #They’re copied out rather than looped through for speed.
    #
    if ( index( $text, 'maketext' ) != -1 || index( $text, 'lextext' ) != -1 || index( $text, 'cptext' ) != -1 || index( $text, 'translatable' ) != -1 ) {    ## no extract maketext
        for my $line ( split m{\n}, $text ) {
            next if index( $line, 'maketext' ) == -1 && index( $line, 'lextext' ) == -1 && index( $line, 'cptext' ) == -1 && index( $line, 'translatable' ) == -1;    ## no extract maketext

            next if index( $line, 'no extract maketext' ) != -1;                                                                                                      ## no extract maketext
            return 1;
        }
    }

    return 0;
}

1;
