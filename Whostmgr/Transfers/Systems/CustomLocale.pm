package Whostmgr::Transfers::Systems::CustomLocale;

# cpanel - Whostmgr/Transfers/Systems/CustomLocale.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

# RR Audit: JNK

use Cpanel::Locale                 ();
use Cpanel::Locale::Utils::Display ();
use Cpanel::SafeRun::Errors        ();

use base qw(
  Whostmgr::Transfers::Systems
);

sub get_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('This restores custom locales.') ];
}

sub get_restricted_available {
    return 0;
}

sub unrestricted_restore {
    my ($self) = @_;

    return $self->import_non_existent_locale();
}

sub restricted_restore {
    my ($self) = @_;

    my ( $ok, $locales_hr ) = $self->_get_archive_locale_file_hash();
    return ( 0, $locales_hr ) if !$ok;

    if ( scalar keys %$locales_hr ) {
        foreach my $locale ( sort keys %$locales_hr ) {
            $self->{'_utils'}->add_skipped_item("$locale locale");
        }

        return ( $Whostmgr::Transfers::Systems::UNSUPPORTED_ACTION, $self->_locale()->maketext( 'Restricted restorations do not allow the “[_1]” module to run.', 'CustomLocale' ) );
    }

    return 1;
}

#For testing
#TODO: Refactor scripts/locale_import so that the test can actually verify what
#finally is done with the restore rather than stopping here.
sub _import_locale_file {
    my ( $self, $locale_path ) = @_;

    return Cpanel::SafeRun::Errors::saferunallerrors( '/usr/local/cpanel/scripts/locale_import', "--import=$locale_path", '--quiet' );
}

sub import_non_existent_locale {
    my ($self) = @_;

    my ( $ok, $locales_hr ) = $self->_get_archive_locale_file_hash();
    return ( 0, $locales_hr ) if !$ok;

    my $output;

    my $extractdir = $self->extractdir();

    my @locale_list            = Cpanel::Locale::Utils::Display::get_locale_list( $self->_locale() );
    my %existing_locale_lookup = map { $_ => undef } @locale_list;

    while ( my ( $locale_name, $locale_path ) = each %$locales_hr ) {
        if ( exists $existing_locale_lookup{$locale_name} ) {
            $self->{'_utils'}->add_skipped_item("$locale_name locale (already exists)");
        }
        else {
            my $out = $self->_import_locale_file($locale_path);
            $output .= $out;
        }
    }

    return ( 1, 'OK', $output );
}

sub _get_archive_locale_file_hash {
    my ($self) = @_;

    my $extractdir = $self->extractdir();

    my %locale_file;

    my $locdir = "$extractdir/locale";

    if ( -d $locdir ) {
        opendir( my $dir_h, $locdir ) or do {
            return ( 0, $self->_locale()->maketext( 'The system failed to open the directory “[_1]” because of an error: [_2]', $locdir, $! ) );
        };

        local $!;
        %locale_file = map {
            do { ( my $s = $_ ) =~ s/\.xml$//; $s }
              => "$locdir/$_"
        } grep { !/^\.\.?$/ } readdir($dir_h);
        if ($!) {
            return ( 0, $self->_locale()->maketext( 'The system failed to read the directory “[_1]” because of an error: [_2]', $locdir, $! ) );
        }

        closedir($dir_h) or do {
            $self->warn( $self->_locale()->maketext( 'The system failed to open the directory “[_1]” because of an error: [_2]', $locdir, $! ) );
        };
    }

    return ( 1, \%locale_file );
}

1;
