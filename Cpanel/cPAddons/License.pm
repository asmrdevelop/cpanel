
# cpanel - Cpanel/cPAddons/License.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::cPAddons::License;

use strict;
use warnings;

use Cpanel                            ();
use Cpanel::cPAddons::Globals::Static ();
use Cpanel::Encoder::Tiny             ();
use Cpanel::Imports;

=head1 NAME

Cpanel::cPAddons::License

=head1 DESCRIPTION

Retrieve or check license info for a cPAddon

=head1 FUNCTIONS

=head2 get_license_info(LICENSE)

Look up additional license info based on the information already available.

=head2 get_license_info(undef, PATH)

Look up additional license info based a file path provided.

=head3 Arguments

Neither argument is required, but you must specify one or the other:

  - LICENSE - String - If specified, this may be one of three things:
    - A path to a file on disk containing license terms
    - A URL to a file containing license terms
    - Plain text containing license terms
  - PATH - String - If specified, this is a relative path underneath the
    cPAddons base (/usr/local/cpanel/cpaddons) directory to a file containing
    license terms.

=head3 Returns

Hash ref containing:

- license - String - The path or URL used to retrieve the license. In the case of
a license whose text was specified as an argument to the function, this field will
be set to "inline" to indicate that the license was specified inline.

- license_text - String - The full text of the license.

- error - String - (Only on failure) The error message.

=cut

sub get_license_info {
    my ( $license, $path ) = @_;

    my $response = {};

    my $content   = '';
    my $error     = '';
    my $base_path = "$Cpanel::cPAddons::Globals::Static::base/$path";

    if ( !$license ) {
        my @file_names = qw(lisc license.txt license LISC LICENSE);
        for my $file_name (@file_names) {
            my $lisc_path = "$base_path/$file_name";
            if ( -e $lisc_path ) {
                $license = $lisc_path;
                last;
            }
        }
    }

    if ( !$license ) {
        my $lisc_path = "$base_path/lisc";
        if ( -e $lisc_path ) {
            $license = $lisc_path;
        }
    }

    if ($license) {
        if ( -e $license ) {

            # License is included in the lisc file shipped with the addon
            if ( open my $fh, '<', $license ) {
                local $/;
                $content = readline $fh;
                close $fh;
            }
            else {
                $error = locale()->maketext(
                    'The system could not open the license [_1]: [_2]',
                    Cpanel::Encoder::Tiny::safe_html_encode_str($license),
                    Cpanel::Encoder::Tiny::safe_html_encode_str($!),
                );
            }
        }
        elsif ( $license =~ m/^https?\:\/\// ) {

            # License is url from the meta-data
            my ( $hostname, $url ) = $license =~ m/https?\:\/\/([^\/]*)(\/.*)$/;
            require Cpanel::HttpRequest;
            $content = Cpanel::HttpRequest->new( 'hideOutput' => 1 )->request(
                'host' => $hostname,
                'url'  => $url,
            );
            $error = locale()->maketext(
                'The system could not retrieve the URL [_1].',
                Cpanel::Encoder::Tiny::safe_html_encode_str($license),
            ) if !$content;
        }
        else {
            # License is text from the meta-data
            $content = $license;
            $license = "inline";
        }
    }

    return {
        license => $license,
        error   => $error,
    } if $error;

    return {
        license      => $license,
        license_text => $content,
    };
}

=head2 check_license(OBJ, INFO, INPUT, INSTALL)

Checks that the license for an addon is valid. This is done before installation.

=head3 Arguments

- OBJ - Cpanel::cPAddons::Obj

- INFO - Hash ref - Module metadata ('meta' field) from the structure returned by Cpanel::cPAddons::Module::get_module_data().

- INPUT - Hash ref - The form data from the user submission

- INSTALL - Hash ref - (Optional)

=head3 Returns

True if valid

False if invalid

=cut

sub check_license {
    my ( $obj, $info, $input, $install ) = @_;

    my $lisc =
      defined $install && ref $install eq 'HASH'
      ? $install->{'vendor_license'}
      : $input->{'vendor_license'};

    if ( defined $info->{'vendor_license'}
        && ref $info->{'vendor_license'} eq 'HASH' ) {
        if ( $info->{'vendor_license'}{'verify_url'}
            && ref $info->{'vendor_license'}{'url_says_its_ok'} eq 'CODE' ) {

            my ( $host, $uri ) = $info->{'vendor_license'}{'verify_url'} =~ m{://([^/]+)/(.*)$};
            require Cpanel::HttpRequest;
            my $html = Cpanel::HttpRequest->new( 'hideOutput' => 1 )->request(
                'host' => $host,
                'url'  => "/$uri?user=$Cpanel::user&lisc=$lisc"
            ) || '';

            $obj->{license_valid} = 1;
            if ( !$info->{'vendor_license'}{'url_says_its_ok'}->($html) ) {
                $obj->{license_valid} = 0;
                $obj->add_error($html);
                return;
            }
        }
        elsif ( ref $info->{'vendor_license'}{'string_is_ok'} eq 'CODE' ) {
            if ( !$info->{'vendor_license'}{'string_is_ok'}->($lisc) ) {
                $obj->{license_valid} = 0;
                $obj->add_error($lisc);
                return;
            }
        }
        else {
            if ( $lisc !~ m/^\w+$/ ) {
                $obj->{license_valid} = 0;
                $obj->add_error( locale()->maketext('A vendor license must contain only numbers, letters, and underscores (_).') );
                return;
            }
        }

        # $lisc is already in $install if we're using $install,
        # so no need to fiddle with it here
        if ( !defined $install || ref $install ne 'HASH' ) {
            $obj->{'vendor_license'} = $lisc;
        }

    }
    return 1;
}

1;
