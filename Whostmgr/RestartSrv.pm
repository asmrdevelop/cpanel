package Whostmgr::RestartSrv;

# cpanel - Whostmgr/RestartSrv.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Whostmgr::UI          ();
use Cpanel::Encoder::Tiny ();
use Cpanel::LoadModule    ();
use Cpanel::Locale ('lh');
use Cpanel::CloseFDs          ();
use Cpanel::Convert::FromHTML ();

sub restartsrv_html_page {    ## no critic qw(ManyArgs) - needs refactor
    my ( $srv, $srvname, $prog, $confirmed, $app_key, %opts ) = @_;

    require Cpanel::Services::List;
    my $srv_pretty_name = Cpanel::Services::List::get_name($srv);
    if ( $srv_pretty_name eq $srv || $srv_pretty_name =~ m/missing/i ) {
        $srv_pretty_name = $srvname;
    }

    # The name feteched from get_name above will often contain HTML, which is rendered as-is in the title element
    # We must strip the HTML before sending for display
    my $text_title = Cpanel::Convert::FromHTML::to_text($srv_pretty_name);
    if ( !$confirmed ) {
        confirmservice( $prog, $srv, $text_title, $app_key, %opts );
        return;
    }

    my @defheader_opts = @{ $opts{'defheader'} || [] };

    Cpanel::LoadModule::load_perl_module('Whostmgr::HTMLInterface');
    Whostmgr::HTMLInterface::defheader( lh()->maketext( "Restarting [_1]", $text_title ), undef, undef, undef, undef, undef, undef, undef, $app_key, @defheader_opts );
    Cpanel::CloseFDs::fast_closefds();
    restartsrv( $srv, $srv_pretty_name );
    Whostmgr::HTMLInterface::deffooter();
    return;
}

sub restartsrv {
    my ( $srv, $srv_pretty_name ) = @_;

    Cpanel::LoadModule::load_perl_module('Whostmgr::HTMLInterface');
    Whostmgr::HTMLInterface::load_statusbox('Restarting Service');
    Whostmgr::UI::setstatus($srv_pretty_name);
    require Cpanel::Services::Restart;
    Cpanel::Services::Restart::restartservice( $srv, 1, 0, \&Cpanel::Encoder::Tiny::safe_html_encode_str );
    Whostmgr::UI::setstatusdone();
    Whostmgr::UI::clearstatus();
    return;
}

sub confirmservice {
    my ( $prog, $srv, $srv_pretty_name, $app_key, %opts ) = @_;

    my @defheader_opts = @{ $opts{'defheader'} || [] };

    Cpanel::LoadModule::load_perl_module('Whostmgr::HTMLInterface');
    Cpanel::LoadModule::load_perl_module('Cpanel::Template');
    Whostmgr::HTMLInterface::defheader( $srv_pretty_name, undef, undef, undef, undef, undef, undef, undef, $app_key, @defheader_opts );

    Cpanel::Template::process_template(
        'whostmgr',
        {
            'print'         => 1,
            'template_file' => 'confirmservice.tmpl',
            'data'          => { 'prog' => $prog, },
        },
    );
    Whostmgr::HTMLInterface::deffooter();
    return;
}

1;
