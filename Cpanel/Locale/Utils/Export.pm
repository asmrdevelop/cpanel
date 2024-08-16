package Cpanel::Locale::Utils::Export;

# cpanel - Cpanel/Locale/Utils/Export.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Locale::Utils::Export

=head1 SYNOPSIS

    # For German:
    my $struct_hr = locale_to_struct('de')

=head1 DESCRIPTION

This module exposes logic to use cPanel’s lexicon.

=cut

#----------------------------------------------------------------------

use Encode ();

use Cpanel::DataStore            ();
use Cpanel::Locale::Utils::Files ();
use Cpanel::Locale::Utils::Paths ();
use Cpanel::Locale::Utils::MkDB  ();
use Cpanel::Themes::Available    ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $struct_hr = locale_to_struct( $LOCALE )

This returns a data structure that represents a locale’s translations.
(Sorry, no details yet on the schema.)

=cut

sub locale_to_struct ($locale) {
    my $struct = {
        'struct_version'          => 1,
        'data_collection_started' => time,
        'locale'                  => $locale,
    };

    foreach my $theme ( '/', Cpanel::Themes::Available::getthemeslist() ) {
        my @en = Cpanel::Locale::Utils::Files::get_file_list( "en", $theme, 0 );
        foreach my $file ( grep { $_ !~ m/Locale\/\Q$locale\E\.pm$/ && $_ !~ m/3rdparty\/conf\/\Q$locale\E/ } Cpanel::Locale::Utils::Files::get_file_list( $locale, $theme, 0 ), @en ) {
            next if !-e $file || -d _;
            next if $file =~ m/\.lock$/;

            $struct->{'payload'}{$theme}{$file}{'is_legacy'} = ( reverse( split( /\//, $file ) ) )[1] eq 'lang' ? 1 : 0;

            $struct->{'payload'}{$theme}{$file}{'mtime'} = ( stat(_) )[7];
            $struct->{'payload'}{$theme}{$file}{'stat'}  = [ stat(_) ];

            my $hr           = $struct->{'payload'}{$theme}{$file}{'is_legacy'} ? Cpanel::Locale::Utils::MkDB::get_hash_of_legacy_file_or_its_cache($file) : Cpanel::DataStore::fetch_ref($file);
            my $file_charset = exists $hr->{'charset'} && $hr->{'charset'}      ? $hr->{'charset'}                                                         : '';
            delete $hr->{'charset'};

            my $needs_re_encode = ( $struct->{'payload'}{$theme}{$file}{'is_legacy'} && $file_charset && $file_charset ne 'utf-8' ) ? 1 : 0;

            $struct->{'payload'}{$theme}{$file}{'data'} = {
                map {
                    my $key = $_;
                    if ($needs_re_encode) {
                        Encode::encode( 'utf-8', Encode::decode( $file_charset, $key ) ) => Encode::encode( 'utf-8', Encode::decode( $file_charset, $hr->{$key} ) );
                    }
                    else {
                        $key => $hr->{$key};
                    }

                } keys %{$hr}
            };
        }
    }

    _merge_pending_to_en($struct);

    $struct->{'data_collection_finished'} = time;

    return $struct;
}

sub _merge_pending_to_en ($struct) {
    my $locale_yaml_root = Cpanel::Locale::Utils::Paths::get_locale_yaml_root();
    my $en_path          = "$locale_yaml_root/en.yaml";
    my $pending          = "$locale_yaml_root/queue/pending.yaml";

    my $payload = $struct->{'payload'}{'/'};
    $payload->{$en_path}{'data'} = {
        %{ $payload->{$pending}{'data'} },
        %{ $payload->{$en_path}{'data'} },
    };

    return;
}

1;
