
# cpanel - Cpanel/API/ImageManager.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::API::ImageManager;

use strict;
use warnings;

use File::Basename ();

use Cpanel                           ();
use Cpanel::Autodie                  ();
use Cpanel::Binaries                 ();
use Cpanel::Exception                ();
use Cpanel::FileUtils::Attr          ();
use Cpanel::FileUtils::Copy          ();
use Cpanel::FileUtils::Move          ();
use Cpanel::SafeDir::MK              ();
use Cpanel::SafeRun::Simple          ();
use Cpanel::Validate::FilesystemPath ();
use Cpanel::Validate::Integer        ();
use Cpanel::Validate::Number         ();

use Cwd ();

use Cpanel::Imports;

our %API = (
    _needs_feature => "cpanelpro_images",
    _needs_role    => 'WebServer',
    get_dimensions => { allow_demo => 1 },
);

# There is no defined MAX INT constant, so I created one
our $MAX_64_BIT_UNSIGNED = ~0;

=head1 MODULE

C<Cpanel::API::ImageManager>

=head1 DESCRIPTION

C<Cpanel::API::ImageManager> provides UAPI wrapper to a few functions
provided by ImageMagick.   These are intended to be replacements for
the functions provided by cPAPI1 so they can be removed.

=head1 EXAMPLES

NOTE: there is an images directory in /home/cptest1 that all of these are referencing
as relative.

=over

=item uapi --user=cptest1 ImageManager get_dimensions image_file=images/myimage.jpeg

=item uapi --user=cptest1 ImageManager convert_file type=png image_file=images/myimage.jpeg

=item uapi --user=cptest1 ImageManager create_thumbnails dir=images width_percentage=25 height_percentage=25

=item uapi --user=cptest1 ImageManager resize_image image_file=images/resize_work/myimage.jpeg save_original_as=images/resize_work/original.jpeg width=100 height=90

=back

=head1 FUNCTIONS

=head2 get_dimensions

Gets the dimensions of the image file provided.

=head3 ARGUMENTS

=over

=item image_file - string

This is the path to an image file to get the dimensions of.   The path can
either be a full path or a relative path from the user's home dir.

=back

=head3 EXAMPLES

=head4 Command Line

    uapi --user=cptest1 ImageManager get_dimensions image_file=images/myimage.jpeg

=head4 Template Toolkit

    [%
        SET result = execute('ImageManager', 'get_dimensions', {'image_file' => full_path_to_file});
    %]

    <p>Height: [% result.data.height %] Width: [% result.data.width %] </p>


=head3 RETURNS

    {
       "module" : "ImageManager",
       "apiversion" : 3,
       "func" : "get_dimensions",
       "result" : {
          "metadata" : {},
          "data" : {
             "width" : "261",
             "height" : "300"
          },
          "messages" : null,
          "status" : 1,
          "warnings" : null,
          "errors" : null
       }
    }

    The width and height of the image file are in the data section as width and height in pixels.

=head3 THROWS

=over

=item Invalid Parameter - When the image file cannot be found or does not exist inside the user's home directory.

=item Invalid Parameter - When the image file is not readable.

=back

=cut

sub get_dimensions {
    my ( $args, $result ) = @_;

    my $image_file = $args->get_length_required('image_file');

    $image_file = _safe_image_file_or_die($image_file);
    my $dimensions = _get_dimensions($image_file);
    if ( !$dimensions ) {
        $result->error( "The system was unable to determine the dimensions for “[_1]”.", $image_file );
        return 0;
    }
    else {
        $result->data($dimensions);
    }

    return 1;
}

=head2 convert_file

Converts an image file to a new image type.

=head3 ARGUMENTS

=over

=item image_file - string

This is the path to an image file to convert to the new type.
The path can either be a full path or a relative path from the user's home dir.

=item type - string

The image type of the converted file such as png, jpeg, gif, etc.

=back

=head3 EXAMPLES

=head4 Command Line

    uapi --user=cptest1 --output=jsonpretty ImageManager convert_file image_file=/home/cptest1/images/myimage.jpeg type=gif

=head4 Template Toolkit

    [%
        SET result = execute('ImageManager', 'convert_file', {'image_file' => full_path_to_file, type => 'png'});
    %]

    <p>Converted path: [% result.data.converted_file %] </p>

=head3 RETURNS

    {
       "func" : "convert_file",
       "module" : "ImageManager",
       "result" : {
          "status" : 1,
          "messages" : null,
          "errors" : null,
          "warnings" : null,
          "metadata" : {},
          "data" : {
             "converted_file" : "/home/cptest1/images/myimage.gif"
          }
       },
       "apiversion" : 3
    }

    The full path to the converted file is in the data section.

=head3 THROWS

=over

=item Invalid Parameter - When the image file cannot be found or does not exist inside the user's home directory.

=item Invalid Parameter - When the image file is not readable.

=back

=cut

sub convert_file {
    my ( $args, $result ) = @_;

    my $image_file = $args->get_length_required('image_file');
    my $new_type   = lc( $args->get_length_required('type') );    # all image extensions are ok as lowercase
                                                                  # image file extensions are only going to be simple alpha characters
    die Cpanel::Exception::create( 'InvalidParameter', "Invalid image type “[_1]”.", [$new_type] ) if ( $new_type !~ m/^[a-z0-9]+$/ );

    $image_file = _safe_image_file_or_die($image_file);
    my $new_file = $image_file;
    $new_file =~ s/\.?[^\.]+$//g;                                 # removes the "last" file extension

    if ( $new_file eq "" ) { $new_file = $image_file; }

    $new_file .= "\.${new_type}";

    if ( -e $new_file ) {
        $result->error( "The system was unable to convert “[_1]” because “[_2]” already exists.", $image_file, $new_file );
        return 0;
    }

    my $rout = Cpanel::SafeRun::Simple::saferunonlyerrors( Cpanel::Binaries::path('convert'), $image_file, $new_file );
    if ( $? || !-e $new_file ) {
        $result->error( "The system was unable to convert “[_1]”: [_2]", $image_file, $rout );
        return 0;
    }
    else {
        $result->data( { 'converted_file' => $new_file } );
    }

    return 1;
}

=head2 create_thumbnails

Converts all image files in a directory to thumbnails in the C<thumbnail> directory.

=head3 ARGUMENTS

=over

=item dir - string

This is the path to a directory of image files.
The path can either be a full path or a relative path from the user's home dir.

A thumbnail directory will be created immediately below "dir".

Example if "dir" is /home/myaccount/images, then a directory /home/myaccount/images/thumbnails is created.

=item width_percentage - number

The percentage to scale the width.

=item height_percentage - number

The percentage to scale the height.

=back

=head3 EXAMPLES

=head4 Command Line

    uapi --user=cptest1 --output=jsonpretty ImageManager create_thumbnails dir=images width_percentage=25 height_percentage=25

=head4 Template Toolkit

    [%
        SET result = execute('ImageManager', 'create_thumbnails',
        {
            'dir' => 'images',
            'width_percentage' => 25,
            'height_percentage' => 25
        });
    %]

    [% FOREACH operation IN result.data %]
        [% IF operation.failed %]
            <strong>[% operation.reason %]</strong>
        [% ELSE %]
            <p>Thumbnail: [% operation.thumbnail_file %] File: [% operation.file %] </p>
        [% END %]
    [% END %]



=head3 RETURNS

    {
       "result" : {
          "warnings" : null,
          "data" : [
             {
                "thumbnail_file" : "/home/cptest1/public_html/thumbnail_work/thumbnails/tn_610_290.jpg",
                "file" : "/home/cptest1/public_html/thumbnail_work/610_290.jpg",
                "reason" : "too many pixels",
                "failed" : 1
             },
             {
                "thumbnail_file" : "/home/cptest1/public_html/thumbnail_work/thumbnails/tn_simpson_drooling.jpeg",
                "file" : "/home/cptest1/public_html/thumbnail_work/simpson_drooling.jpeg",
             }
          ],
          "errors" : null,
          "status" : 1,
          "messages" : null,
          "metadata" : {
             "transformed" : 1
          }
       },
       "func" : "create_thumbnails",
       "module" : "ImageManager",
       "apiversion" : 3
    }

=over

=item thumbnail_file - the file generated or would have been generated.

=item file - the file that the thumbnail is generated from.

=item failed - if the system was unable to create the thumbnail this will be present with
the value of 1, and reason will have the error message.

=item reason - is not present on success, but contains an error message when the operation failed.

=back

=head3 THROWS

=over

=item Invalid Parameter - When the dir does not exist or is invalid.

=item Invalid Parameter - When the width_percentage is not a positive rational number.

=item Invalid Parameter - When the height_percentage is not a positive rational number.

=back

=cut

sub create_thumbnails {
    my ( $args, $result ) = @_;

    my $dir               = $args->get_length_required('dir');
    my $width_percentage  = $args->get_length_required('width_percentage');
    my $height_percentage = $args->get_length_required('height_percentage');

    $dir = _validate_dir_or_die($dir);
    if ( !-d $dir ) {
        $result->error( "The directory “[_1]” does not exist.", $dir );
        return 0;
    }

    Cpanel::Validate::Number::rational_number($width_percentage);
    Cpanel::Validate::Number::rational_number($height_percentage);

    die Cpanel::Exception::create( 'InvalidParameter', "“[_1]” must be a positive integer.", ["width_percentage"] )  if ( $width_percentage <= 0.0 );
    die Cpanel::Exception::create( 'InvalidParameter', "“[_1]” must be a positive integer.", ["height_percentage"] ) if ( $height_percentage <= 0.0 );

    $width_percentage  = ( $width_percentage / 100.0 );
    $height_percentage = ( $height_percentage / 100.0 );

    my $thumbnails_dir = $dir . 'thumbnails';
    if ( !-d $thumbnails_dir ) {
        my $ret = Cpanel::SafeDir::MK::safemkdir( $thumbnails_dir, 0744 );
        if ( !$ret || !-d $thumbnails_dir ) {
            $result->error( "The system was unable to create the thumbnail directory “[_1]”: [_2]", $thumbnails_dir, $! );
            return 0;
        }
    }

    my @out_thumbnails;
    my $did_any_succeed = 0;

    my @thumbnails = _get_thumbnail_list( $dir, $width_percentage, $height_percentage );
    foreach my $thumbnail (@thumbnails) {
        my $file     = $thumbnail->{'file'};
        my $new_file = $thumbnail->{'new_file'};

        if ( !exists $thumbnail->{'new_width'} ) {
            my $reason = locale->maketext( "The system was unable to determine the dimensions for “[_1]”: [_2]", $file, $thumbnail->{'message'} );
            push(
                @out_thumbnails,
                {
                    'failed'         => 1,
                    'file'           => $file,
                    'thumbnail_file' => $new_file,
                    'reason'         => $reason,
                }
            );
        }
        else {
            my $rout = Cpanel::SafeRun::Simple::saferunonlyerrors( Cpanel::Binaries::path('convert'), $file, '-thumbnail', $thumbnail->{'new_width'} . 'x' . $thumbnail->{'new_height'}, $new_file );
            if ( $? || !-e $new_file ) {
                my $reason = locale->maketext( "The system was unable to create the thumbnail for “[_1]”: [_2]", $file, $! );
                push(
                    @out_thumbnails,
                    {
                        'failed'         => 1,
                        'file'           => $file,
                        'thumbnail_file' => $new_file,
                        'reason'         => $reason,
                    }
                );
            }
            else {
                $did_any_succeed = 1;
                push(
                    @out_thumbnails,
                    {
                        'file'           => $file,
                        'thumbnail_file' => $new_file,
                    }
                );
            }
        }
    }

    $result->data( \@out_thumbnails );

    return $did_any_succeed;
}

=head2 resize_image

Resizes an image_file to a new size.

=head3 ARGUMENTS

=over

=item image_file - string

This is the path to an image file to convert to the new type.
The path can either be a full path or a relative path from the user's home dir.

=item width - integer

The width in pixels for the new image.

=item height - integer

The height in pixels for the new image.

=item save_original_as - string

This is an optional parameter.  If this parameter is passed a copy of the original image is copied to this path.

=back

=head3 EXAMPLES

=head4 Command Line

    uapi --user=cptest1 --output=jsonpretty ImageManager resize_image image_file=images/myimage.gif width=200 height=250 save_original_as=images/original.gif

=head4 Template Toolkit

    [%
    SET result = execute('ImageManager', 'resize_image',
    {
        'image_file' => 'images/myimage.gif',
        'width' => 200,
        'height' => 250,
        'save_original_as'  => 'images/myimage_original.gif'
    });
    %]
    <p>Resized: [% result.data %] </p>

=head3 RETURNS

The full path of the resized file is in the data section.

    {
       "apiversion" : 3,
       "result" : {
          "messages" : null,
          "errors" : null,
          "metadata" : {},
          "data" : "/home/cptest1/images/myimage.gif",
          "warnings" : null,
          "status" : 1
       },
       "func" : "resize_image",
       "module" : "ImageManager"
    }

=head3 THROWS

=over

=item Invalid Parameter - When the image file cannot be found or does not exist inside the user's home directory.

=item Invalid Parameter - When the image file is not readable.

=item Invalid Parameter - When the width is not a positive integer.

=item Invalid Parameter - When the height is not a positive integer.

=back

=cut

sub resize_image {
    my ( $args, $result ) = @_;

    my $image_file = $args->get_length_required('image_file');
    my $width      = $args->get_length_required('width');
    my $height     = $args->get_length_required('height');

    my $save_original_as = $args->get('save_original_as');

    $image_file = _safe_image_file_or_die($image_file);

    my $attributes = Cpanel::FileUtils::Attr::get_file_or_fh_attributes($image_file);
    if ( $attributes->{'IMMUTABLE'} ) {
        $result->error( "The system was unable to resize the image “[_1]” because the immutable attribute is set.", $image_file );
        return 0;
    }

    if ( $attributes->{'APPEND_ONLY'} ) {
        $result->error( "The system was unable to resize the image “[_1]” because the append only attribute is set.", $image_file );
        return 0;
    }

    Cpanel::Validate::Integer::unsigned_and_less_than( $width,  $MAX_64_BIT_UNSIGNED );
    Cpanel::Validate::Integer::unsigned_and_less_than( $height, $MAX_64_BIT_UNSIGNED );

    if ($save_original_as) {
        $save_original_as = _get_safe_image_file($save_original_as);
        if ( -e $save_original_as ) {
            $result->error( "The system was unable to resize the image “[_1]” because “[_2]” already exists.", $image_file, $save_original_as );
            return 0;
        }
    }

    my $tmp_file = $image_file . '.cPscale';
    my $size_str = "${width}x${height}";

    my $rout = Cpanel::SafeRun::Simple::saferunonlyerrors( Cpanel::Binaries::path('convert'), $image_file, '-resize', $size_str, $tmp_file );
    if ( $? || !-f $tmp_file ) {
        $result->error( "The system was unable to resize the image “[_1]”: [_2]", $image_file, $rout );
        return 0;
    }
    else {
        if ($save_original_as) {
            $save_original_as = _get_safe_image_file($save_original_as);
            my $ret = Cpanel::FileUtils::Copy::safecopy( $image_file, $save_original_as );
            if ( !$ret || !-e $save_original_as ) {
                $result->error( "The system was unable to copy file “[_1]” to “[_2]”: [_3]", $image_file, $save_original_as, $! );
                return 0;
            }
        }

        my $ret = Cpanel::FileUtils::Move::safemv( '-f', $tmp_file, $image_file );
        if ( !$ret ) {
            $result->error( "The system was unable to move file “[_1]” to “[_2]” ([_3]). Resize operation failed.", $tmp_file, $image_file, $! );
            return 0;
        }

        $result->data($image_file);
    }

    return 1;
}

=head1 INTERNAL SUBROUTINES

=head2 _validate_dir_or_die

Validate the directory that it is safe from user input.  Directory should be in the user's home dir.

=head3 ARGUMENTS

=over

=item dir - string

The directory to validate.

=back

=head3 RETURNS

The possibly reworked dir.  The dir is normalized to have a trailing slash.

=cut

sub _validate_dir_or_die {
    my ($dir) = @_;

    my $original = $dir;

    Cpanel::Validate::FilesystemPath::die_if_any_relative_nodes($dir);
    Cpanel::Validate::FilesystemPath::validate_or_die($dir);    # further checks for nul bytes and other invalids

    if ( substr( $dir, 0, 1 ) ne '/' ) {
        $dir = $Cpanel::abshomedir . '/' . $dir;
    }

    $dir = Cwd::abs_path($dir) || '';

    die Cpanel::Exception::create( 'InvalidParameter', 'Directory “[_1]” does not exist.', [$original] )
      if !$dir || !-d $dir;

    die Cpanel::Exception::create( 'InvalidParameter', 'Files are restricted to user’s home directory: [_1]', [$dir] ) if ( $dir !~ m{^$Cpanel::abshomedir} );

    $dir .= '/' if ( substr( $dir, -1, 1 ) ne '/' );

    return $dir;
}

=head2 _get_safe_image_file

Make sure the path of an image file is under the user's home directory.

=head3 ARGUMENTS

=over

=item image_file - string

This is the path to an image file.
The path can either be a full path or a relative path from the user's home dir.

=back

=head3 RETURNS

The possibly reworked image_file path.

=cut

sub _get_safe_image_file {
    my ($image_file) = @_;

    my ( $filename, $dir, $suffix ) = File::Basename::fileparse($image_file);

    if ( $dir eq './' ) {
        $dir = $Cpanel::abshomedir . '/';
    }
    else {
        $dir = _validate_dir_or_die($dir);
    }

    $image_file = $dir . $filename;
    return $image_file;
}

=head2 _safe_image_file_or_die

Get a version of the image file path that is under the user's home directory or die if it does not exist.

=head3 ARGUMENTS

=over

=item image_file - string

This is the path to an image file to convert to the new type.
The path can either be a full path or a relative path from the user's home dir.

=back

=head3 RETURNS

The possibly reworked image_file path.

=head3 THROWS

=over

=item Invalid Parameter - When the image file cannot be found or does not exist inside the user's home directory.

=item Invalid Parameter - When the image file is not readable.

=back

=cut

sub _safe_image_file_or_die {
    my ($image_file) = @_;

    $image_file = _get_safe_image_file($image_file);

    if ( !-f $image_file ) {
        die Cpanel::Exception::create( 'InvalidParameter', "The file “[_1]” does not exist in the user’s home directory.", [$image_file] );
    }

    if ( !-r $image_file ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The file “[_1]” is not readable.', [$image_file] );
    }

    return $image_file;
}

=head2 _get_dimensions

Return the dimensions of the image file.

=head3 ARGUMENTS

=over

=item image_file - Path to the image

    my $img_dim = _get_dimensions($image_file);
    say "Height: $img_dim->{height}";
    say "Width: $img_dim->{width}";

=back

=head3 RETURNS

Returns a hash ref with the width and height.

    {
        'width' => 100,
        'height' => 110
    }

=cut

sub _get_dimensions {
    my ($image_file) = @_;

    my $rout = Cpanel::SafeRun::Simple::saferunnoerror( Cpanel::Binaries::path('identify'), $image_file );
    if ( $rout =~ /(\d+)x(\d+)/ ) {
        return { 'width' => $1, 'height' => $2 };
    }

    return;
}

=head2 _get_thumbnail_list

Return an array of image files in a directory with information for making it into a thumbnail.

=head3 ARGUMENTS

=over

=item dir - string

This is the path of the directory to look for image files.

=item width_percentage - number

The percentage you want the width to be adjusted by.

=item height_percentage - number

The percentage you want the width to be adjusted by.

=back

=head3 RETURNS

Returns an array of information about image files in the dir and what the name of a possible thumbnail and it's dimesions.

    [
        {
            'file' => '/home/cptest1/images/myfile.jpeg',
            'old_width' => 100,
            'old_height' => 110,
            'new_width' => 65,
            'new_height' => 75,
            'new_file' => '/home/cptest1/images/thumbnails/tn_myfile.jpeg',
        },
        { ...
    ]

=over

=item file

The full path to the original image file.

=item old_width

The width of 'file' image. If this value is missing, we were unable to get the dimensions.

=item old_height

The height of 'file' image. If this value is missing, we were unable to get the dimensions.

=item new_width

The width that the thumbnail should be. If this value is missing, we were unable to get the dimensions.

=item new_height

The height that the thumbnail should be. If this value is missing, we were unable to get the dimensions.

=item new_file

The thumbnail file.

=back

=cut

sub _get_thumbnail_list {
    my ( $dir, $width_percentage, $height_percentage ) = @_;

    require Math::Round;

    my @out_list;
    Cpanel::Autodie::opendir( my $dir_fh, $dir );
    while ( my $file = readdir($dir_fh) ) {
        my $path = $dir . $file;
        next if ( $file eq '.' || $file eq '..' || -d $path );
        my $dims = _get_dimensions($path);
        if ($dims) {
            my $width        = $dims->{'width'};
            my $height       = $dims->{'height'};
            my $thumb_width  = Math::Round::round( $width * $width_percentage );
            my $thumb_height = Math::Round::round( $height * $height_percentage );
            push @out_list, {
                'file'       => $path,
                'old_width'  => $width,
                'old_height' => $height,
                'new_width'  => $thumb_width,
                'new_height' => $thumb_height,
                'new_file'   => $dir . "thumbnails/tn_$file",
                'message'    => '',
            };
        }
        else {
            # without the dimensions the outer layer will know this failed
            # to get the dimensions
            push @out_list, {
                'file'     => $path,
                'new_file' => $dir . "thumbnails/tn_$file",
                'message'  => "$|",
            };
        }
    }
    Cpanel::Autodie::closedir($dir_fh);
    return @out_list;
}

1;
