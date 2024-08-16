package Cpanel::Locale::Utils;

# cpanel - Cpanel/Locale/Utils.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

BEGIN {
    eval { require CDB_File; };
}

use Cpanel::Locale::Utils::Paths ();

# MEMORY!
#  Do not load Cpanel () from this module as it
#  does not required it most of the time and it will
#  always already be loaded if it does
#
#  use Cpanel                            ();
#

$Cpanel::Locale::Utils::i_am_the_compiler = 0;

my $logger;

sub _logger {
    require Cpanel::Logger;
    $logger ||= Cpanel::Logger->new();
}

# perl -MCpanel::Locale::Utils -MData::Dumper -e 'my %lexicon;Cpanel::Locale::Utils::get_readonly_tie($ARGV[0],\%lexicon);print Dumper(\%lexicon);' path/to/file

################################################
# TODO: make these upgrade/downgrade lexicon to a Tie::Hash::ReadonlyStack object if it is not tied()
#
# sub add_file_lexicon_override_hash {
#     my ( $lh, $locale, $name, $cdb_file ) = @_;
#     return if !-e $cdb_file;
#
#     my %orig;
#     get_readonly_tie( $cdb_file, \%orig );
#     return $lh->add_lexicon_override_hash( $locale, $name, \%orig );
# }
#
# sub add_file_lexicon_fallback_hash {
#     my ( $lh, $locale, $name, $cdb_file ) = @_;
#     return if !-e $cdb_file;
#
#     my %orig;
#     get_readonly_tie( $cdb_file, \%orig );
#     return $lh->add_lexicon_fallback_hash( $locale, $name, \%orig );
# }
#
# sub del_file_lexicon_hash {
#     my ( $lh, $locale, $name ) = @_;
#     $lh->del_lexicon_hash( $locale, "$name.local" );
#     $lh->del_lexicon_hash( $locale, $name );
#     return 1;
# }
################################################

sub get_readonly_tie {
    my ( $cdb_file, $cdb_hr ) = @_;
    if ( !$cdb_file ) {
        _logger()->warn('Undefined CDB file specified for readonly operation');
        return;
    }
    elsif ( !$INC{'CDB_File.pm'} || !exists $CDB_File::{'TIEHASH'} ) {
        _logger()->warn("Failed to load CDB_File.pm") if $^X ne '/usr/bin/perl';
        return;
    }

    my $tie_obj = tie %{$cdb_hr}, 'CDB_File', $cdb_file;

    if ( !$tie_obj && !-e $cdb_file ) {
        _logger()->warn("Missing CDB file $cdb_file specified for readonly operation");
        return;

    }

    # Verify that the data is okay.
    eval { exists $cdb_hr->{'__VERSION'} };
    if ($@) {
        $tie_obj = undef;
        untie %$cdb_hr;
    }

    if ( !$tie_obj ) {
        _logger()->warn("CDB_File could not get read-only association to '$cdb_file': $!");
    }

    return $tie_obj;
}

sub create_cdb {
    my ( $cdb_file, $cdb_hr ) = @_;

    if ( !$cdb_file ) {
        _logger()->warn('Undefined CDB file specified for writable operation');
        return;
    }

    return CDB_File::create( %{$cdb_hr}, $cdb_file, "$cdb_file.$$" );
}

sub get_writable_tie {
    require Carp;
    Carp::confess("cdb files are not writable");
}

sub init_lexicon {
    my ( $langtag, $hr, $version_sr, $encoding_sr ) = @_;
    my $cdb_file;
    my $db_root = Cpanel::Locale::Utils::Paths::get_locale_database_root();

    for my $file ( $Cpanel::CPDATA{'RS'} ? ("themes/$Cpanel::CPDATA{RS}/$langtag.cdb") : (), "$langtag.cdb" ) {    # PPI NO PARSE - Only include Cpanel() when some other module uses it
        if ( -e "$db_root/$file" ) {
            $cdb_file = "$db_root/$file";
            last;
        }
    }

    if ( !$cdb_file ) {
        if ( -e Cpanel::Locale::Utils::Paths::get_locale_yaml_root() . "/$langtag.yaml" && !$Cpanel::Locale::Utils::i_am_the_compiler ) {
            _logger()->info(qq{Locale needs to be compiled by root (/usr/local/cpanel/bin/build_locale_databases --locale=$langtag)});
        }
        return;
    }

    # if the if() block above is ever changed to compile the yaml file then we might want to re-detect that it still !-e:
    # die "hello root, run: /usr/local/cpanel/bin/build_locale_databases --locale=$langtag to see why it didn't compile" if !-e $cdb_file;

    my $cdb_tie = get_readonly_tie( $cdb_file, $hr );

    if ( exists $hr->{'__VERSION'} && ref $version_sr ) {
        ${$version_sr} = $hr->{'__VERSION'};
    }

    if ( ref $encoding_sr ) {

        # DO NOT USE THIS KEY, utf-8 only, and if you *must* then do it in the package properly
        # if ( exists $hr->{'__Encoding'} ) {
        #     ${$encoding_sr} = $hr->{'__Encoding'};
        # }
        ${$encoding_sr} ||= 'utf-8';
    }

    return $cdb_file;
}

sub init_package {
    my ($caller) = caller();

    my ($langtag) = reverse( split( /::/, $caller ) );

    # it is either soft refs or a string eval or some major symbol table voodoo
    no strict 'refs';
    no warnings 'once';

    ${ $caller . '::CDB_File_Path' } ||= init_lexicon( "$langtag", \%{ $caller . '::Lexicon' }, \${ $caller . '::VERSION' }, \${ $caller . '::Encoding' }, );

    return;
}

1;
