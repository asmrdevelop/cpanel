package Cpanel::API::Branding;

# cpanel - Cpanel/API/Branding.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)
#
use Cpanel::Encoder::URI       ();
use Cpanel::Template           ();
use Cpanel::Themes::Serializer ();
use Cpanel::cpanel             ();
use Cpanel::Locale             ();
use Cpanel::DynamicUI::App     ();
use Cpanel::Path::Safety       ();
use Cpanel::StatCache          ();

my $locale;

## note: like Cpanel::Branding::Lite, hard-coded to 1, and never changed...
my $isopt = 1;

sub include {
    my ( $args, $result ) = @_;
    my ( $file, $skip_default, $raw, $data ) = $args->get(qw(file skip_default raw data));

    require Cpanel::Branding::Lite::Package;
    require Cpanel::Branding::Lite;

    my $brandingpkg = Cpanel::Branding::Lite::Package::_getbrandingpkg();

    ## $isvar=1, $inline=0, $needfile=1, $checkmain=1
    ## currently, $needfile=1 causes returns under all conditions before $isvar and $inline
    ##   are used
    my $include_file = Cpanel::Branding::Lite::_file( $file, 1, $brandingpkg, 0, 1, $skip_default, 1 );
    if ($include_file) {
        if ( $include_file =~ m/\.tt$/ ) {
            my $template_args = {
                'template_file' => $include_file,
            };

            if ($data) {
                $template_args->{'data'} = $data;
            }

            ## copied from cpanel.pl's <?cptt>
            ## UAPI: $str_or_obj_or_ref_output is one of the following: an error string,
            ##   $Template::ERROR, or a reference to successful output
            my ( $status, $str_or_obj_or_ref_output ) = Cpanel::Template::process_template(
                'cpanel',
                $template_args,
            );
            if ($status) {
                $result->data($$str_or_obj_or_ref_output);
                return 1;
            }
            return;
        }
        else {
            local $Cpanel::IxHash::Modify = 'safe_html_encode';

            my $scalar = Cpanel::cpanel::_wrap_include( $include_file, ( $raw ? 4 : 0 ), 1 );
            $result->data($scalar);
            return 1;
        }
    }
}

#-------------------------------------------------------------------------------------------------
# Scope:
#   public
# Name:
#   get_application_information
# Desc:
#   gets the application information from dynamicuiconf file for a single application
# Arguments:
#   app_key - string - unique identifier for the application (currently its file parameter in dynamicuiconf)
# Returns:
#   Hash - Contains the properties associated to application requested (itemdesc, width, height, url, description ... )
#-------------------------------------------------------------------------------------------------
sub get_application_information {

    my ( $args, $result ) = @_;
    my ($app_key) = $args->get(qw(app_key));

    # Setups the globals
    _initialize();

    my $dbrandconf;

    # using eval because Cpanel::DynamicUI::App::load_dynamic_ui_conf does not provide correct error handling
    eval { $dbrandconf = Cpanel::DynamicUI::App::load_dynamic_ui_conf(); };
    if ($@) {
        my $err = $@;
        $result->error( 'Could not load dynamicuiconf: [_1]', $err );
    }

    my $app_info;
    if ( $app_key && exists $dbrandconf->{$app_key} ) {
        $app_info = $dbrandconf->{$app_key};
    }

    $result->data($app_info);
    return 1;
}

#-------------------------------------------------------------------------------------------------
# Scope:
#   public
# Name:
#   get_available_applications
# Desc:
#   retrieve the applist from dynamicui
#   with groups and index
# Arguments:
#   none
# Returns:
#   groups - an arrayref of groups with each as in an arrayref of items
#   index  - an index of where each app is in the groups arrayref
#-------------------------------------------------------------------------------------------------
sub get_available_applications {
    my ( $args, $result ) = @_;

    $result->data( Cpanel::DynamicUI::App::get_available_applications( 'nvarglist' => $args->get('nvarglist') || '', 'arglist' => $args->get('arglist') || '', 'need_description' => 1 ) );
    return 1;
}

#-------------------------------------------------------------------------------------------------
# Scope:
#   public
# Name:
#   get_applications
# Desc:
#   gets information for a list of applications from dynamicui
# Arguments:
#   app_keys: a comma separated list of application keys, if no application
#   keys are provided, all applications in dynamicui will be listed
# Returns:
#   Hash - each key points to a hash of attributes for an application
#-------------------------------------------------------------------------------------------------
sub get_applications {
    my ( $args, $result ) = @_;
    my ($app_keys) = $args->get(qw(app_keys));

    my @list_of_keys = ();
    if ($app_keys) {
        @list_of_keys = split( /,/, $app_keys );
    }

    # Setups the globals
    _initialize();

    my $dbrandconf;

    # using eval because Cpanel::DynamicUI::App::load_dynamic_ui_conf does not provide correct error handling
    eval { $dbrandconf = Cpanel::DynamicUI::App::load_dynamic_ui_conf(); };
    if ($@) {
        my $err = $@;
        $result->error( 'Could not load dynamicuiconf: [_1]', $err );
    }

    if ( scalar @list_of_keys ) {
        $result->data( { map { $_ => $dbrandconf->{$_} } grep { $_ && exists $dbrandconf->{$_} } @list_of_keys } );    ## no critic (ProhibitVoidMap)
    }
    else {
        $result->data($dbrandconf);
    }

    return 1;
}

#-------------------------------------------------------------------------------------------------
# Scope:
#   public
# Name:
#   get_information_for_applications
# Desc:
#   gets information for a list of applications from sitemap.json
# Arguments:
#   app_keys - string - comma separated list of identifiers for the applications
#                       (the "key" parameter for each item in sitemap.json)
#   docroot  - string - document root for the theme
#                       (where the sitemap.json file can be found)
# Returns:
#   Hash of Hashs - Contains the properties associated to applications requested
#                   (itemdesc, width, height, url, description ... )
#-------------------------------------------------------------------------------------------------
sub get_information_for_applications {
    my ( $args, $result ) = @_;
    my ($app_keys) = $args->get(qw(app_keys));
    $app_keys ||= '';

    # Setups the globals
    _initialize();

    my $appname = ( $Cpanel::appname eq 'webmail' ) ? 'webmail' : 'frontend';
    my ($docroot) = $args->get('docroot') // _get_ulc() . '/base/' . $appname . '/' . $Cpanel::CPDATA{'RS'};

    my ( $serializer_obj, $items );
    $items = [];
    eval {
        $serializer_obj = Cpanel::Themes::Serializer::get_serializer_obj( "JSON", $docroot, $Cpanel::user );
        $serializer_obj->build_data_tables;
        $items = $serializer_obj->get_items();
    };

    if ($@) {
        my $err = $@;
        $result->error( 'Could not load sitemap: [_1]', $err );
    }

    my %list_apps = map { $_ => 1 if $_ !~ m/^\s+$/ } split( /,/, $app_keys );
    my %app_info;

    if ( scalar keys(%list_apps) ) {
        %app_info = map { $_->{key} => $_ } grep { ref $_ eq 'HASH' && $list_apps{ $_->{key} } } @{$items};
    }
    else {
        %app_info = map { $_->{key} => $_ } grep { ref $_ eq 'HASH' && $_->{key} } @{$items};
    }

    $result->data( \%app_info );
    return 1;
}

sub _known_ext {
    my ( $imgtype, $image, $subtype, $method ) = @_;

    require Cpanel::Branding::Lite;

    my $config = Cpanel::Branding::Lite::load_theme_config();

    $image   //= '';
    $subtype //= '';

    my $known_ext = (
        ( $imgtype && $image eq 'heading' && $subtype eq 'compleximg' )
        ? 'jpg'
        : ( $imgtype && $image eq 'heading' && $subtype eq 'img' ) ? 'png'

        : ( $method  && index( $method, 'only_filetype_gif' ) > -1 )      ? 'gif'
        : ( $method  && index( $method, 'skip_filetype_gif' ) > -1 )      ? 'jpg'
        : ( $method  && index( $method, 'snap_to_smallest_width' ) > -1 ) ? 'png'
        : ( $method  && index( $method, 'scale_60percent' ) > -1 )        ? 'png'
        : ( $imgtype && $imgtype eq 'icon' )                              ? $config->{'icon'}->{'format'}
        :                                                                   undef
    );
    return $known_ext;
}

#-------------------------------------------------------------------------------------------------
# Scope:
#   private (by convention)
# Name:
#   _initialize
# Desc:
#   initialize the logger and local system if they are not already initialized.
# Arguments:
#   N/A
# Returns:
#   N/A
#-------------------------------------------------------------------------------------------------
sub _initialize {
    $locale ||= Cpanel::Locale->get_handle();
    return 1;
}

sub _get_ulc {
    return '/usr/local/cpanel';
}

my $allow_demo = { allow_demo => 1 };

our %API = (
    include                          => $allow_demo,
    get_application_information      => $allow_demo,
    get_available_applications       => $allow_demo,
    get_applications                 => $allow_demo,
    get_information_for_applications => $allow_demo,
);

1;
