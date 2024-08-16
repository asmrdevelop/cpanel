#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - whostmgr/docroot/cgi/locale_duplicate.cgi
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Cpanel::Encoder::URI            ();
use Cpanel::Form                    ();
use Cpanel::Locale                  ();
use Cpanel::Locale::Utils::3rdparty ();
use Cpanel::Locale::Utils::Display  ();
use Cpanel::Locale::Utils::Paths    ();
use Cpanel::Locale::Utils::XML      ();
use Cpanel::StringFunc::Trim        ();
use Cpanel::TempFile                ();
use Cpanel::Template                ();
use Cpanel::Template::Interactive   ();
use Whostmgr::ACLS                  ();
use Whostmgr::HTMLInterface         ();

print "Content-type: text/html\r\n\r\n";

Whostmgr::ACLS::init_acls();

if ( !Whostmgr::ACLS::checkacl('locale-edit') ) {

    Whostmgr::HTMLInterface::defheader();
    print <<'EOM';

<br />
<br />
<div><h1>Permission denied</h1></div>
</body>
</html>
EOM
    exit;
}

my $security_token = $ENV{'cp_security_token'} || '';

my $formref = Cpanel::Form::parseform();
my $locale  = Cpanel::Locale->get_handle();

my %lookup;
@lookup{ Cpanel::Locale::Utils::Display::get_locale_list($locale) } = ();

if ( !$formref->{'verify_overwrite'} ) {

    my $existing_target = '';
    if ( $formref->{'into'} eq 'i_tag' ) {
        require Cpanel::CPAN::Locales;
        $formref->{'display_name'} = Cpanel::StringFunc::Trim::ws_trim( $formref->{'display_name'}    || '' );
        $formref->{'i_tag'}        = Cpanel::CPAN::Locales::get_i_tag_for_string( $formref->{'i_tag'} || $formref->{'display_name'} );
        $formref->{'i_tag'}        = ''                  if $formref->{'i_tag'} eq 'i_';
        $existing_target           = $formref->{'i_tag'} if exists $lookup{ $formref->{'i_tag'} };
    }
    else {
        $existing_target = $formref->{'into_locale'} if exists $lookup{ $formref->{'into_locale'} };
    }

    if ( !exists $lookup{ $formref->{'locale'} } ) {
        locale_duplicate();    # will do error
    }
    elsif ($existing_target) {
        Cpanel::Template::process_template(
            'whostmgr',
            {
                'template_file' => 'locale_duplicate_verify_overwrite.tmpl',
                'breadcrumburl' => '/scripts9/locale_duplicate_form',
                'data'          => {
                    'existing_target'   => $existing_target,
                    'back_query_string' => join( '&', map { "$_=" . Cpanel::Encoder::URI::uri_encode_str( $formref->{$_} ) } qw(locale into_locale fallback_locale character_orientation numf_type into i_tag display_name) ),
                    'encoded_formref'   => { ( map { ( Cpanel::Encoder::URI::uri_encode_str($_) => Cpanel::Encoder::URI::uri_encode_str( $formref->{$_} ) ) } sort keys %{$formref} ) },
                },
            },
        );
    }
    else {
        locale_duplicate();
    }
}
else {
    locale_duplicate();
}

sub locale_duplicate {    ## no critic(ProhibitExcessComplexity)
    my @available = Cpanel::Locale::Utils::Display::get_locale_list($locale);

    $formref->{'locale'} = '' if !grep { $_ eq $formref->{'locale'} } @available;
    my $into = '';

    if ( $formref->{'into'} eq 'i_tag' ) {
        require Cpanel::CPAN::Locales;
        $formref->{'display_name'} = Cpanel::StringFunc::Trim::ws_trim( $formref->{'display_name'}    || '' );
        $formref->{'i_tag'}        = Cpanel::CPAN::Locales::get_i_tag_for_string( $formref->{'i_tag'} || $formref->{'display_name'} );
        $formref->{'i_tag'}        = '' if $formref->{'i_tag'} eq 'i_';

        $formref->{'fallback_locale'} ||= '';
        if ( !$formref->{'fallback_locale'} ) {
            $formref->{'fallback_locale'} = '' if !grep { $_ eq $formref->{'fallback_locale'} } @available;
        }

        if ( $formref->{'character_orientation'} ne 'left-to-right' && $formref->{'character_orientation'} ne 'right-to-left' ) {
            $formref->{'character_orientation'} = '';
        }

        if ( $formref->{'numf_type'} ne '1' && $formref->{'numf_type'} ne '2' ) {
            $formref->{'numf_type'} = '';
        }

        $into = $formref->{'i_tag'};
    }
    else {
        $formref->{'into_locale'} = '' if !grep { $_ eq $formref->{'into_locale'} } Cpanel::Locale::Utils::Display::get_non_existent_locale_list($locale);
        $into = $formref->{'into_locale'};
    }

    Cpanel::Template::Interactive::process_template(
        'whostmgr',
        {
            'print'         => 1,
            'template_file' => 'locale_duplicate.tmpl',
            'breadcrumburl' => '/scripts9/locale_duplicate_form',
            'data'          => {
                'formref'           => $formref,
                'back_query_string' => join( '&', map { "$_=" . Cpanel::Encoder::URI::uri_encode_str( $formref->{$_} ) } qw(locale into_locale fallback_locale character_orientation numf_type into i_tag display_name) ),
                'cpanel_provided'   => \%Cpanel::Locale::Utils::3rdparty::cpanel_provided,
                'copy_target'       => $into,
                'copy_args'         => [ $formref->{'locale'}, $into, $formref->{'display_name'}, $formref->{'fallback_locale'}, $formref->{'character_orientation'}, $formref->{'numf_type'} ],
                'copy_locale'       => sub {
                    my ( $copy_tag, $to_tag, $i_disp, $i_fall, $i_orient, $i_numf ) = @{ $_[0] };
                    my $i_config_path = Cpanel::Locale::Utils::Paths::get_i_locales_config_path();

                    print "Copying '$copy_tag' to '$to_tag'...\n\n";

                    # Generate random temporary directory for export file.
                    # This will be owned by root and automatically cleaned up on destruction.
                    # We are creating the file for now, but locale_export will unlink and overwrite it.

                    my $temp_obj = Cpanel::TempFile->new();
                    my $dir      = $temp_obj->dir();
                    my $file     = $temp_obj->file( { 'path' => $dir, suffix => 'xml' } );

                    system( '/usr/local/cpanel/scripts/locale_export', "--locale=$copy_tag", "--export-$copy_tag=$file", '--dumper-format' );

                    print "\nUpdating data for import ... \n\n";

                    #### edit XML ####

                    my $error;
                    if ( my $struct = Cpanel::Locale::Utils::XML::get_data_struct_from_xml_file( $file, \$error ) ) {

                        # edit 'locale', change to $to_tag (and other meta)
                        $struct->{'struct_version'}          = 1;
                        $struct->{'data_collection_started'} = time;
                        $struct->{'locale'}                  = $to_tag;
                        my $i_tag_info_created = 0;

                        foreach my $theme ( keys %{ $struct->{'payload'} } ) {
                            foreach my $path ( keys %{ $struct->{'payload'}{$theme} } ) {
                                my $orig_path = $path;
                                my $new_path  = $path;

                                my ( $file_part, @reversed_path ) = reverse( split /\//, $orig_path );
                                my $path_part = join( '/', reverse(@reversed_path) );

                                if ( $struct->{'payload'}{$theme}{$orig_path}{'is_legacy'} ) {
                                    my $i_less_to_tag = $to_tag;
                                    $i_less_to_tag =~ s{^i_}{};                       # how do determine how to move lang/italian to lang/ that gets mapped back to $to_tag ? you use the .legacy_duplicate. naming hack
                                    $file_part     =~ s/^.+\.legacy_duplicate\.//;    # prevent multiple copies from building up a long name
                                    $new_path = "$path_part/$i_less_to_tag.legacy_duplicate.$file_part";
                                }
                                else {
                                    my ( $file, $ext ) = split( /\./, $file_part, 2 );
                                    $new_path = "$path_part/$to_tag" . ( $ext ? ".$ext" : '' );
                                }

                                # edit paths names
                                $struct->{'payload'}{$theme}{$new_path} = delete $struct->{'payload'}{$theme}{$orig_path};

                                if ( $new_path =~ m{^\Q$i_config_path\E} ) {
                                    if ( $to_tag =~ m{^i_} ) {

                                        # edit Cpanel::Locale::Utils::Paths::get_i_locales_config_path() entries w/ $i_disp, $i_fall, $i_orient
                                        $struct->{'payload'}{$theme}{$new_path}{'data'}{'display_name'}          = $i_disp;
                                        $struct->{'payload'}{$theme}{$new_path}{'data'}{'fallback_locale'}       = $i_fall;
                                        $struct->{'payload'}{$theme}{$new_path}{'data'}{'character_orientation'} = $i_orient;
                                        $struct->{'payload'}{$theme}{$new_path}{'data'}{'numf_type'}             = $i_numf;
                                        $i_tag_info_created                                                      = 1;

                                    }
                                    else {

                                        # delete panel::Locale::Utils::Paths::get_i_locales_config_path() entry
                                        delete $struct->{'payload'}{$theme}{$new_path};
                                    }
                                    next;
                                }

                                # in case $copy_tag is onesided we need to ensure YAML files are not == add missing values to make not onesided
                                if ( !$struct->{'payload'}{$theme}{$new_path}{'is_legacy'} ) {
                                    for my $key ( keys %{ $struct->{'payload'}{$theme}{$new_path}{'data'} } ) {
                                        $struct->{'payload'}{$theme}{$new_path}{'data'}{$key} = $key if !defined $struct->{'payload'}{$theme}{$new_path}{'data'}{$key} || $struct->{'payload'}{$theme}{$new_path}{'data'}{$key} eq '';
                                    }
                                }
                            }
                            if ( !$i_tag_info_created && $to_tag =~ m{^i_} ) {
                                my $target = $i_config_path . '/' . $to_tag . '.yaml';
                                $struct->{'payload'}{'/'}{$target}{'data'}{'display_name'}          = $i_disp;
                                $struct->{'payload'}{'/'}{$target}{'data'}{'fallback_locale'}       = $i_fall;
                                $struct->{'payload'}{'/'}{$target}{'data'}{'character_orientation'} = $i_orient;
                                $struct->{'payload'}{'/'}{$target}{'data'}{'numf_type'}             = $i_numf;
                            }

                        }

                        $struct->{'data_collection_finished'} = time;

                        #### /edit XML ###

                        my $error;
                        if ( Cpanel::Locale::Utils::XML::save_data_struct_to_xml_file( $file, $struct, \$error ) ) {
                            system( '/usr/local/cpanel/scripts/locale_import', "--import=$file" );    # rebuilds DB for just the one locale unless you pass it --no-rebuild
                        }
                        else {
                            print "Could not save XML for '$to_tag':\n\t$error\n";
                        }
                    }
                    else {
                        print "Could not fetch XML for '$copy_tag':\n\t$error\n";
                    }

                    return;    # or else this gets a '1' printed
                },
            },
        },
    );
    return;
}
