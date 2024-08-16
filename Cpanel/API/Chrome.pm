package Cpanel::API::Chrome;

# cpanel - Cpanel/API/Chrome.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Template ();
use Cpanel           ();

###
# The purpose of this module is to provide the DOM for chrome around pages
# in an API call.  This is so that non-TT grammars can still present a UI that looks
# like their cpanel theme.
#
# Meaning of chrome in the context of this module is defined at:  http://www.nngroup.com/articles/browser-and-gui-chrome/
###

=head1 SUBROUTINES

=over 4

=item get_dom()

Return a hash containing two keys: header & footer than contain all the data before and after the body-content div

 params:
    page_title => the title of the page (will be prepaended with "cPanel - ")

 returns:
    {
        header => string containing the part of the page before your content
        footer => stringing containing the part of the page AFTER your content
    }

=cut

sub get_dom {
    my ( $args, $result ) = @_;

    my ($page_title) = $args->get('page_title');
    my ($app_key)    = $args->get('app_key');

    my $theme_root   = '/usr/local/cpanel/base/frontend/' . $Cpanel::CPDATA{'RS'} . '/';
    my $process_file = "${theme_root}/_assets/empty.html.tt";

    unless ( -e $process_file ) {

        # read: x3 mode.
        return _get_legacy_dom( $args, $result, $theme_root );
    }

    # run the template
    my ( $status, $output ) = Cpanel::Template::process_template(
        'cpanel',
        {
            'print'         => 0,
            'template_file' => $process_file,
            'page_title'    => $page_title,
            'app_key'       => $app_key,
        },
    );

    if ( !$status ) {
        $result->error( 'Error in processing template: [_1]', $output );
        return 0;
    }

    # ensure that we have output
    $output = ref $output eq 'SCALAR' ? $$output : $output;
    $result->data( { 'output' => $output, 'result' => $status } );

    # split the output into headers and footers
    my $split_key = '<!--custom_framing-->';

    my $header_end   = index( $output, $split_key );
    my $footer_start = $header_end + length $split_key;

    my $header = substr( $output, 0, $header_end );
    my $footer = substr( $output, $footer_start );

    # return the data!
    $result->data(
        {
            'header' => $header,
            'footer' => $footer,
        }
    );
    return 1;
}

sub _get_legacy_dom {
    my ( $args, $result ) = @_;
    $result->error('legacy themes are not supported at this time.');
    return 0;
}

=back

=cut

our %API = (
    get_dom => { allow_demo => 1 },
);

1;
