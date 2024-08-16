# cpanel - Whostmgr/Customizations.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::Customizations;

=head1 NAME

Whostmgr::Customizations -- Handles API and other usage of customization functions introduced with Jupiter

=head1 SYNOPSIS

    use Whostmgr::Customizations ();

    my $add_result = eval {Whostmgr::Customizations::add ("root", "cpanel", "jupiter", {"brand"=>{}})};
    #Did we get a result?
    if ($add_result) {
        #Was the change accepted?
        if ($add_result->{'validated'}) {
            print "Success!\n";
            #Review non-fatal warnings (if any)
            if ($add_result->{'warnings'}) {
                foreach my $warning (@{$add_result->{'warnings'}}) {print "   Warning: $warning\n";}
            }
        } else {
            #Validation failed and the entry was rejected,
            foreach my $error (@{$add_result->{'errors'}}) {print "   Validation Error: $error\n";}
        }
    } else {
        print "Critical Error: $@\n";
    }

    my $brand = Whostmgr::Customizations::get ("root", "cpanel", "jupiter");
    if ($brand) {
        print "Success\n";
    } else {
        print "Not found\n";
    }

    my $delete_result = eval{Whostmgr::Customizations::delete ("root", "cpanel", "jupiter")};
    if ($delete_result == 1) {
        print "Success\n";
    } else {
        if ($delete_result == 0) { print "Not found.\n"; }
        if ($@) { print "Error: $@"; }
    }

=head1 DESCRIPTION

Contains methods for adding, retrieving, and deleting customization and branding data.

=cut

use strict;
use warnings;
use MIME::Base64 ();
use Umask::Local ();

use Cpanel::Autodie  ();
use Cpanel::JSON     ();
use Cpanel::LoadFile ();
use Whostmgr::Customization::Files();
use Cpanel::Async::EasyLock;
use Cpanel::PromiseUtils;
use Cpanel::Set           ();
use Cpanel::Validate::URL ();
use Cpanel::Themes::Get();

my $data_path = '/var/cpanel/customizations';
use constant DEFAULT_SECTION => 'default';
use constant VALID_THEMES    => ( Cpanel::Themes::Get::cpanel_default_theme() );
use constant VALID_APPS      => qw ( cpanel webmail );
use constant STRUCTURE => {
    brand => {
        logo => {
            forLightBackground => 'base64',
            description        => 'string',
            forDarkBackground  => 'base64',
        },
        colors => {
            primary => 'color',
            link    => 'color',
            accent  => 'color',
        },
        favicon => 'base64',
    },
    documentation => {
        url => 'uri',
    },
    help => {
        url => 'uri',
    },
};

use constant REQUIRED => {};

=head1 SUBROUTINES

=head2 add ($USER, $APPLICATION, $THEME, $BRAND)

Adds branding information to customization data, given an application (such as "cpanel" or "webmail"), a theme, and a 'brand' data structure.

=over

=item * $USER - String - Reseller or root user name to add customizations for.

=item * $APPLICATION - String - The application associated with this brand (such as "cpanel" or "webmail")

=item * $THEME - String - The theme associated with this brand.

=item * $BRAND - hash data - Branding data following the spec shown below:

=over

    {
        'brand' => {
            'colors' => {
                'accent'  => '#00FF00',
                'link'    => '#0000FF',
                'primary' => '#FF0000'
            },
            'logo' => {
                'description' => 'The logo for this brand.',
                'forDarkBackground' => 'Base64 encoded string, replaces the cPanel logo and company name for dark backgrounds',
                'forLightBackground' => 'Base64 encoded string, replaces the cPanel log and company name for light backgrounds',
            }
            'favicon' => 'Base64 encoded string',
        }
        'help' => {
            url => 'Optional help link',
        }
        'documentation' => {
            url => 'Optional documentation link',
        }
    }

=back

=back

=head3 RETURNS

TRUE if the addition was successful, FALSE if it was rejected.

=cut

sub add {
    my ( $user, $application, $theme, $new_data ) = @_;
    if ( !$user ) { die "The 'user' parameter is required."; }

    _validate_app_and_theme( $application, $theme );

    my $valid = _validate_data($new_data);
    if ( $valid->{'validated'} == 1 ) {
        my $lock = _lock( $user, $application, $theme );
        my $data = _load( $user, $application, $theme );
        if ( !defined $data->{ ( DEFAULT_SECTION() ) } ) {
            $data->{ DEFAULT_SECTION() } = {};
        }
        _combine_old_and_new( $data->{ DEFAULT_SECTION() }, $new_data );
        _save( $user, $application, $theme, $data );
    }
    return $valid;
}

=head2 get ($USER, $APPLICATION, $THEME)

Retrieves branding information from customization data for a given application and theme.

=over

=item * $USER - String - Reseller or root user name to retrieve customization data for.

=item * $APPLICATION - String - The application associated with this brand (such as "cpanel" or "webmail")

=item * $THEME - String - The theme associated with this brand.

=back

=head3 RETURNS

A data structure just like the branding structure that add() accepts.

=cut

sub get {
    my ( $user, $application, $theme ) = @_;
    return undef unless $user;

    _validate_app_and_theme( $application, $theme );
    my $data = _load( $user, $application, $theme );
    if ($data) {
        _combine_old_and_new( $data->{ DEFAULT_SECTION() }, {} );
        return $data->{ DEFAULT_SECTION() };
    }
    return _empty();
}

=head2 delete ($USER, $APPLICATION, $THEME, $PATH)

Deletes an entry, given an application and theme.

If a path is provided, only the element requested will be deleted, otherwise the entire section will be deleted.

If the json file is left empty after deletion, this will delete the entire file.

=over

=item * $USER - String - Reseller or root user name to delete customization data from.

=item * $APPLICATION - String - The application associated with this brand (such as "cpanel" or "webmail")

=item * $THEME - String - The theme associated with this brand.

=item * $PATH - String - Optional partial path to delete in the dataset.

=back

=head3 RETURNS

TRUE if the deletion was successful, FALSE if the entry does not exist.

=cut

sub delete {
    my ( $user, $application, $theme, $path ) = @_;
    return unless $user;

    _validate_app_and_theme( $application, $theme );
    my $lock = _lock( $user, $application, $theme );
    my $data = _load( $user, $application, $theme );

    $path //= '';
    $path = DEFAULT_SECTION() . ( $path ? ".$path" : '' );
    my ( $el, $name ) = _find( $data, $path );
    if ($el) {
        delete $el->{$name};
        if ( scalar keys %{$data} == 0 ) {    #Is there anything left in this file?
            _unlink( _select_file( $user, $application, $theme ) );    #If not, delete it entirely.
        }
        else {
            _save( $user, $application, $theme, $data );               #If there's still other data, save it.
        }
        return 1;
    }
    else {
        return 0;
    }
}

sub _find {
    my ( $data, $path ) = @_;
    my @parts     = split( /[.]/, $path );
    my $last_part = pop @parts;

    my $leaf = $data;
    foreach my $part (@parts) {
        return ( undef, undef ) if !exists $leaf->{$part};
        $leaf = $leaf->{$part};
    }
    return ( $leaf, $last_part );
}

sub _load {
    my ( $user, $app, $theme ) = @_;
    my $file = _select_file( $user, $app, $theme );
    if ( !$file ) { return; }    #No filename was generated - panic with grace and return null

    my $data;
    my $json = Cpanel::LoadFile::load_if_exists($file);
    if ($json) {
        $data = Cpanel::JSON::Load($json);
    }

    return $data;
}

sub _save {
    my ( $user, $app, $theme, $data ) = @_;

    _mkdir_if_not_exists($user);

    my $file = _select_file( $user, $app, $theme );
    my $result;
    {
        my $original = Umask::Local->new(022);
        $result = eval { Cpanel::JSON::DumpFile( $file, $data ); };
        umask($original);
    }
    return $result;
}

sub _mkdir_if_not_exists {
    my ($user) = @_;

    Cpanel::Autodie::mkdir_if_not_exists( $data_path, 0755 );

    my $dir = $data_path;
    if ( $user eq 'root' ) {
        $dir = $dir . '/brand';
    }
    else {
        $dir = $dir . '/resellers';
    }
    Cpanel::Autodie::mkdir_if_not_exists( $dir, 0755 );

    unless ( $user eq 'root' ) {
        $dir = $dir . '/' . $user;
        Cpanel::Autodie::mkdir_if_not_exists( $dir, 0755 );
    }

    return;
}

sub _select_file {
    my ( $user, $app, $theme ) = @_;
    return Whostmgr::Customization::Files::get_customization_file( $user, $app, $theme );
}

sub _lock {
    my ( $user, $app, $theme ) = @_;
    my $lock_id = $user . "_" . $app . "_" . $theme;    #Underscore is interpreted as part of the variable names
    return Cpanel::PromiseUtils::wait_anyevent( Cpanel::Async::EasyLock::lock_exclusive_p($lock_id) )->get();
}

sub _validate_app_and_theme {
    my ( $application, $theme ) = @_;

    if ( ( !$application ) || ( !grep { $_ eq $application } VALID_APPS ) ) {
        die( "Invalid application: Must be one of the following (" . _stringify_apps() . ")." );
    }

    if ( ( !$theme ) || ( !grep { $_ eq $theme } VALID_THEMES ) ) {
        die( "Invalid theme: Must be one of the following (" . _stringify_themes() . ")." );
    }
    return 1;
}

sub _stringify_apps {
    return join " ", +VALID_APPS;
}

sub _stringify_themes {
    return join " ", +VALID_THEMES;
}

sub _empty {
    my ( $empty, $template ) = @_;
    $empty    //= {};
    $template //= STRUCTURE;

    foreach my $key ( keys %{$template} ) {
        if ( ref $template->{$key} eq 'HASH' ) {
            $empty->{$key} = {};
            _empty( $empty->{$key}, $template->{$key} );
        }
        else {
            $empty->{$key} = '';
        }
    }

    return $empty;
}

sub _combine_old_and_new {
    my ( $old, $new, $template ) = @_;
    $template //= STRUCTURE;

    # we intentionally upgrade the whole
    # object to match the new schema so
    # on subsequent updates we don't have
    # to keep expanding the structure
    # in a piecemeal fashion.
    foreach my $key ( keys %{$template} ) {
        if ( ref $template->{$key} eq 'HASH' ) {
            $old->{$key} = {} if !$old->{$key};
            _combine_old_and_new( $old->{$key}, $new->{$key}, $template->{$key} );
        }
        else {
            if ( defined $new->{$key} ) {
                $old->{$key} = $new->{$key};
            }
            elsif ( !defined $old->{$key} ) {
                $old->{$key} = '';
            }
        }
    }

    return;
}

sub _validate_data {
    my ( $data, $template, $name, $result ) = @_;
    $template //= STRUCTURE;
    $name     //= '';
    $result   //= {
        errors   => [],
        warnings => [],
    };

    foreach my $k ( Cpanel::Set::difference( [ keys %$data ], [ keys %$template ] ) ) {
        push @{ $result->{errors} }, "Unrecognized key '$k' in " . ( $name ? "'$name'" : 'top level' ) . ".";
    }

    foreach my $k ( keys %$template ) {
        my $fullname = ( $name ? "$name.$k" : "$k" );
        if ( !exists $data->{$k} ) {
            if ( REQUIRED->{$fullname} ) {
                push @{ $result->{errors} }, "No entry found for required field '$fullname'.";
            }
            else {
                push @{ $result->{warnings} }, "No entry found for '$fullname'.";
            }
        }
        elsif ( ref $template->{$k} eq 'HASH' && defined $data->{$k} ) {
            _validate_data( $data->{$k}, $template->{$k}, "$fullname", $result );
        }
        elsif ( !defined $data->{$k} || $data->{$k} eq '' ) {
            push @{ $result->{warnings} }, "No value found for '$fullname'.";
        }
        elsif ( $template->{$k} eq 'base64' ) {
            if ( $data->{$k} && !_validate_base64( $data->{$k} ) ) {
                push @{ $result->{errors} }, "Invalid Base64 data found in '$fullname'.";
            }
        }
        elsif ( $template->{$k} eq 'color' ) {
            if ( $data->{$k} && !_validate_hex_color( $data->{$k} ) ) {
                push @{ $result->{errors} }, "Invalid hex color value for '$fullname'.";
            }
        }
        elsif ( $data->{$k} && $template->{$k} eq 'uri' ) {
            if ( !_validate_url( $data->{$k} ) ) {
                push @{ $result->{errors} }, "Invalid URL value for '$fullname'.";
            }
        }
        elsif ( $data->{$k} && $template->{$k} eq 'string' ) {
            if ( !_validate_string( $data->{$k} ) ) {
                push @{ $result->{errors} }, "Invalid value for '$fullname'.";
            }
        }
    }

    $result->{'validated'} = ( @{ $result->{errors} } == 0 ) ? 1 : 0;
    return $result;
}

sub _validate_base64 {
    my ($encoded) = @_;
    if ( !$encoded ) { return 0; }

    # there is at least one edge-case with this method of validation
    # Mozilla uses RFC4648, which allows the use of extra padding--
    # Cpanel::Validate::Base64 would fail this
    require Cpanel::Validate::Base64;
    return eval { Cpanel::Validate::Base64::validate_or_die($encoded) };
}

sub _validate_hex_color {
    my ($color) = @_;
    return $color =~ /^#([A-Fa-f0-9]{6})$/;
}

sub _validate_url {
    my ($url) = @_;
    return 0 if $url !~ m{^(https?:)?//}i;    # for some reason the url checker does not check the protocol. Require: //, http://, or https://
    return Cpanel::Validate::URL::is_valid_url($url);
}

sub _validate_string {
    my ($string) = @_;

    # Placeholder
    return 1;
}

sub _unlink {
    my ($file) = @_;
    return unlink($file);
}

1;
