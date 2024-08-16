package Cpanel::Server::Handlers::Httpd::ErrorPage;

# cpanel - Cpanel/Server/Handlers/Httpd/ErrorPage.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Server::Handlers::Httpd::ErrorPage

=head1 SYNOPSIS

    my $html = Cpanel::Server::Handlers::Httpd::ErrorPage::get_html(
        http_code => 404,
        http_host => 'somedomain.com',
        message_html => 'Some <span>html</span>.',
    );

=head1 DESCRIPTION

This module produces a simple error page for cpsrvd’s standard-port HTTP
service.

=cut

#----------------------------------------------------------------------

use Cpanel::Encoder::Tiny               ();
use Cpanel::HTTP::StatusCodes           ();
use Cpanel::Locale                      ();
use Cpanel::Services::Ports             ();
use Cpanel::Redirect                    ();
use Cpanel::ConfigFiles                 ();
use Cpanel::Server::Type::Role::Webmail ();
use Cpanel::Server::Type                ();

use constant TEMPLATE => <<END;
<!DOCTYPE html>
<html>
    <head>
        <title>%reason</title>

        <style type="text/css">
            body {
                font-family: "Open Sans", helvetica, arial, sans-serif;
            }

            .applinks,
            .copyright {
                margin-top: 25px;
            }

            .copyright {
                font-size: 9.33333px;
                text-align: center;
            }

            span.applogin {
                display: inline-block;

                background-repeat: no-repeat;
                background-size: contain;
                padding-right: 200px;
                padding-bottom: 20px;
            }

            span.applogin > svg {
                height: 1em;
                width: auto;
                vertical-align: middle;
            }

            img.applogin {
                object-fit: cover;
            }

            a, a:visited, a:hover {
                text-decoration: none;
            }
        </style>
    </head>

    <body>
        <h2>HTTP error %http_code: %reason</h2>

        <p>%message_html</p>

        <ul class="applinks">%applinks_html</ul>

        <p class="copyright">Copyright © %year cPanel, Inc.</p>
    </body>
</html>
END

use constant APPLINK_TEMPLATE => <<END;
<li><a href="%url">%text</a></li>
END

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $html = get_html( %OPTS )

%OPTS is:

=over

=item * C<http_code> - The HTTP response code.

=item * C<http_host> - The name given in the HTTP C<Host> header.

=item * C<message_html> - The message to display in the page body, in HTML.

=back

=cut

sub get_html {
    my (%opts) = @_;

    my $url_domain = Cpanel::Redirect::getserviceSSLdomain( 'cpanel', $opts{'http_host'} );

    my $lh = Cpanel::Locale->get_handle();

    my $svc_port_hr = \%Cpanel::Services::Ports::SERVICE;

    my @applinks = (
        {
            url  => "https://$url_domain:$svc_port_hr->{'whostmgrs'}",
            text => $lh->maketext( 'Log in to [_1]', _make_img( 'whm-RGB-v42015.svg', 'WHM' ) ),
        },
    );

    if ( !Cpanel::Server::Type::is_dnsonly() ) {
        unshift @applinks, {
            url  => "https://$url_domain:$svc_port_hr->{'cpanels'}",
            text => $lh->maketext( 'Log in to [_1]', _make_img( 'cpanel-logo-RGB-v42015.svg', 'cPanel' ) ),
        };

        if ( Cpanel::Server::Type::Role::Webmail->is_enabled() ) {
            unshift @applinks, {
                url  => "https://$url_domain:$svc_port_hr->{'webmails'}",
                text => $lh->maketext( 'Log in to [_1]', _make_img( 'webmail-RGB-v42015.svg', 'Webmail' ) ),
            };
        }
    }

    my $applinks_html = join(
        "\n",
        map { _process_template( APPLINK_TEMPLATE(), $_ ) } @applinks,
    );

    my @hard_coded = (
        applinks_html => $applinks_html,

        reason => $Cpanel::HTTP::StatusCodes::STATUS_CODES{ $opts{'http_code'} },

        year => 1900 + ( gmtime() )[5],
    );

    my %var = ( %opts, @hard_coded );

    $var{message_html} = Cpanel::Encoder::Tiny::safe_html_encode_str( $var{message_html} );

    return _process_template( TEMPLATE(), \%var );
}

sub _process_template {
    my ( $tmpl, $vars_hr ) = @_;

    return $tmpl =~ s/\%([_a-z]+)/$vars_hr->{$1}/gr;
}

sub _make_img {
    my ( $filename, $title ) = @_;

    my $path = "$Cpanel::ConfigFiles::CPANEL_ROOT/img-sys/$filename";

    use Cpanel::LoadFile;
    my $svg = Cpanel::LoadFile::load($path);

    return qq[<span class="applogin" title="$title">$svg</span>];
}

1;
