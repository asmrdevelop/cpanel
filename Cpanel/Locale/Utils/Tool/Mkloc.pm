package Cpanel::Locale::Utils::Tool::Mkloc;

# cpanel - Cpanel/Locale/Utils/Tool/Mkloc.pm         Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::DataStore ();
use Cpanel::Locale::Utils::Tool;    # indent(), style()
use Cpanel::Locale::Utils::Files ();
use Cpanel::Themes::Available    ();
use Cpanel::SafeRun::Simple      ();
use Cpanel::SafeDir::RM          ();
use Cpanel::SafeDir::Read        ();
use Cpanel::Locale::Utils        ();

sub subcmd {

    print style( 'info', 'Removing any existing i_cp_* locales …' ) . "\n";
    _remove_any_i_cp_locales();

    print style( 'info', 'Forcing a rebuild of the “en” database …' ) . "\n";
    Cpanel::SafeRun::Simple::saferun(qw(/usr/local/cpanel/bin/build_locale_databases --locale=en --clean));

    print style( 'info', 'Loading “en” data bases …' ) . "\n";

    # create hash for en CDB data, this will include the pending queue phrases.
    my %en_cdb;
    Cpanel::Locale::Utils::get_readonly_tie( '/var/cpanel/locale/en.cdb', \%en_cdb ) || die "Could not load “/var/cpanel/locale/en.cdb”: $!";

    my %en_jupiter_cdb;
    Cpanel::Locale::Utils::get_readonly_tie( '/var/cpanel/locale/themes/jupiter/en.cdb', \%en_jupiter_cdb ) || die "Could not load “/var/cpanel/locale/themes/jupiter/en.cdb”: $!";

    print style( 'info', 'Determining list of i_cp_* locales …' ) . "\n";
    my @i_cp_locales = _get_valid_i_cp_locales();

    for my $i_cp_loc (@i_cp_locales) {
        print style( 'info', "Processing “$i_cp_loc” …" ) . "\n";

        # $ns already loaded in _get_valid_i_cp_locales()
        my $ns = "Cpanel::Locale::Utils::Tool::Mkloc::$i_cp_loc";

        my %special_locale;

        # First jupiter …
        for my $phrase ( keys %en_jupiter_cdb ) {

            # _get_valid_i_cp_locales() already made sure the method exists
            $special_locale{$phrase} = $ns->create_target_phrase( $phrase, $en_jupiter_cdb{$phrase} );
        }

        # … then root, overwriting anything that also happened to exist
        # in jupiter since they should be the same. (Otherwise the theme support
        # is probably being misused as a theming/branding system.)
        # Worst case is an expected value, an jupiter edit perhaps, will not be used.
        # That is not a problem here since these are dev/QA locales and you
        # would have the same problem (but in reverse) if you reversed priority.
        # We could add more complex logic later if it ever becomes an actual problem.
        for my $phrase ( keys %en_cdb ) {

            # _get_valid_i_cp_locales() already made sure the method exists
            $special_locale{$phrase} = $ns->create_target_phrase( $phrase, $en_cdb{$phrase} );
        }

        my $yaml = "/usr/local/cpanel/locale/$i_cp_loc.yaml";
        Cpanel::DataStore::store_ref( $yaml, \%special_locale ) || die "Could not write “$yaml”: $!";

        if ( $ns->can('get_i_tag_config_hr') ) {
            my $conf = "/var/cpanel/i_locales/$i_cp_loc.yaml";
            Cpanel::DataStore::store_ref( $conf, $ns->get_i_tag_config_hr() ) || die "Could not write “$conf”: $!";
        }
    }

    print style( 'info', 'Building the databases for the i_cp_* locales …' ) . "\n";

    # compile new locales:
    Cpanel::SafeRun::Simple::saferun( qw(/usr/local/cpanel/bin/build_locale_databases  --clean), map { "--locale=$_" } @i_cp_locales );

    print style( 'info', 'Done building i_cp_* locales.' ) . "\n";
    return;
}

sub _remove_any_i_cp_locales {
    for my $i_cp_loc_yaml ( Cpanel::SafeDir::Read::read_dir('/usr/local/cpanel/locale/') ) {

        # Could be done in second arg to read_dir() but that seems cumbersome when it is in a for statement
        next if $i_cp_loc_yaml !~ m/\Ai_cp_[a-z0-9_]+\.yaml\z/;    #  no uppercase A-Z since it should be normalized already

        my $i_cp_loc = $i_cp_loc_yaml;
        $i_cp_loc =~ s{.*?([^/]+)\.yaml$}{$1};

        for my $theme ( '/', Cpanel::Themes::Available::getthemeslist() ) {
            for my $file ( Cpanel::Locale::Utils::Files::get_file_list( $i_cp_loc, $theme, 1 ) ) {
                if ( -l $file || ( -e _ && !-d _ ) ) {
                    unlink $file or die "Could not unlink “$file”: $!";
                }
                elsif ( -d _ ) {
                    Cpanel::SafeDir::RM::safermdir($file) || die "Could not remove “$file”: $!";
                }
            }
        }
    }
    return;
}

sub _get_valid_i_cp_locales {
    my @i_cp_locales;
    my $path = $INC{"Cpanel/Locale/Utils/Tool/Mkloc.pm"};
    $path =~ s/\.pm$//;

  PM:
    for my $i_cp_loc_pm ( Cpanel::SafeDir::Read::read_dir($path) ) {

        # Could be done in second arg to read_dir() but that seems cumbersome when it is in a for statement
        next if $i_cp_loc_pm !~ m/\.pm\z/;

        my $i_cp_loc = $i_cp_loc_pm;
        $i_cp_loc =~ s{.*?([^/]+)\.pm$}{$1};
        my $ns = "Cpanel::Locale::Utils::Tool::Mkloc::$i_cp_loc";

        if ( index( $i_cp_loc, 'i_cp_' ) != 0 ) {
            print indent(1) . style( 'error', "Skipping “$i_cp_loc” since it does not begin with “i_cp_” …" ) . "\n";
            next PM;
        }

        eval "require $ns;";
        if ($@) {
            print indent(1) . style( 'error', "Skipping “$i_cp_loc” since it could not be loaded …" ) . "\n";
            my $err = $@;
            $err .= "\n" if $err !~ m/\n$/;
            print indent(2) . $err;
            next PM;
        }

        {
            if ( !defined eval { $ns->can('create_target_phrase') } ) {
                print indent(1) . style( 'error', "Skipping “$i_cp_loc” since it does not implement “create_target_phrase()” …" ) . "\n";
                next PM;
            }
        }

        push @i_cp_locales, $i_cp_loc;
    }

    return @i_cp_locales;
}

1;
