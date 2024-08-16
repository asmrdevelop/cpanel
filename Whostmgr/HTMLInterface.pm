package Whostmgr::HTMLInterface;

# cpanel - Whostmgr/HTMLInterface.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)

use Cpanel::LoadFile                   ();
use Cpanel::JSON                       ();
use Cpanel::Template                   ();
use Cpanel::Template::Plugin::Whostmgr ();
use Cpanel::Finally                    ();
use Cpanel::Version::Full              ();
use Whostmgr::Session                  ();    # PPI USE OK - used below

my $copyright;

BEGIN {
    $copyright = ( localtime(time) )[5] + 1900;
}

our $DISABLE_JSSCROLL = 0;

my %LOADED              = ( '/yui/container/assets/container.css' => 1 );    #now preloaded into the master css sheet
my $printed_jsscrollend = 0;
my $sentdefheader       = 0;
my $sentdeffooter       = 0;
my $brickcount          = 0;
my $ensure_deffooter;

# This variable sometimes holds a Cpanel::Finally.
# It needs to happen before global destruction.

END {
    undef $ensure_deffooter;
}

sub report_license_error {
    my $error = shift;
    my $licservermessage;
    if ( -e '/usr/local/cpanel/logs/license_error.display' ) {
        $licservermessage = Cpanel::LoadFile::loadfile('/usr/local/cpanel/logs/license_error.display');
    }
    Cpanel::Template::process_template(
        'whostmgr',
        {
            'print'         => 1,
            'template_file' => '/usr/local/cpanel/base/unprotected/lisc/licenseerror_whm.tmpl',
            'data'          => {
                'liscerror'        => $error,
                'licservermessage' => $licservermessage
            },
        }
    );
    exit 1;
}

sub simpleheading {
    my $head = shift;
    return print qq{<h3>$head</h3>};
}

sub deffooter {
    undef $ensure_deffooter;
    return if $sentdeffooter++;
    Cpanel::Template::process_template(
        'whostmgr',
        {
            'print'                        => 1,
            'template_file'                => 'master_templates/_deffooter.tmpl',
            'hide_header'                  => $_[0] || undef,
            'skipsupport'                  => $_[1] || undef,
            'inside_frame_or_tab_or_popup' => $_[2] || undef,
            'theme'                        => $_[3] || "yui",
        },
    );

    return;
}

sub defheader {    ## no critic qw(Subroutines::RequireArgUnpacking)
    return if $sentdefheader++;

    my $hide_header                  = $_[5] || undef;
    my $inside_frame_or_tab_or_popup = $_[6] || undef;
    my $theme                        = $_[7] || 'yui';
    my $app_key                      = $_[8] || '';

    #Figure out what the app_key is if this is a plugin which neglected to pass appkey (pretty much all of them)
    if ( !$app_key ) {
        my $cf = '/var/cpanel/pluginscache.yaml';
        require Cpanel::CachedDataStore;
        my $plugindata = -e $cf && Cpanel::CachedDataStore::loaddatastore($cf);
        if ( ( ref $plugindata eq 'Cpanel::CachedDataStore' ) && ( ref $plugindata->{'data'}->{'addons'} eq 'ARRAY' ) ) {
            foreach my $app ( @{ $plugindata->{'data'}->{'addons'} } ) {
                next unless $app->{cgi} && $app->{uniquekey};
                if ( $_[2] =~ m/\Q$app->{cgi}\E$/ ) {
                    $app_key = "plugins_$app->{uniquekey}";
                    last;
                }
            }
        }
    }

    # Args after index 8 are key/value pairs passed directly to the template.

    $ensure_deffooter = Cpanel::Finally->new(
        sub {
            deffooter( $hide_header, undef, $inside_frame_or_tab_or_popup, $theme );
        }
    );

    Cpanel::Template::process_template(
        'whostmgr',
        {
            'print'                        => 1,
            'template_file'                => 'master_templates/_defheader.tmpl',
            'header'                       => $_[0] || undef,
            'icon'                         => $_[1] || undef,
            'breadcrumburl'                => $_[2] || undef,
            'skipbreadcrumb'               => $_[3] || undef,
            'skipheader'                   => $_[4] || undef,
            'hide_header'                  => $hide_header,
            'inside_frame_or_tab_or_popup' => $inside_frame_or_tab_or_popup,
            'theme'                        => $theme,
            'app_key'                      => $app_key,
            @_[ 9 .. $#_ ],
        },
    );

    return;
}

#should be removed once all the perl invocations of this are moved to TT
sub getbggif {
    return Cpanel::Template::Plugin::Whostmgr->getbggif();
}

sub starthtml {
    my ( undef, $returnstr, $extrastyle ) = @_;
    local $Cpanel::App::appname = 'whostmgr';    #make sure we get the right magic revision module

    my $sthtml = ${
        Cpanel::Template::process_template(
            'whostmgr',
            {
                'template_file' => '_starthtml.tmpl',
                'extrastyle'    => $extrastyle,
            },
        )
    };

    if ($returnstr) {
        $sthtml =~ s/\"/\\\"/g;
        return $sthtml;
    }
    else {
        print $sthtml;
    }
}

sub brickstart {
    my ( $title, $align, $percent, $padding ) = @_;
    if ( !defined $percent ) { $percent = '100%'; }
    if ( !defined $align )   { $align   = 'center'; }
    if ( !defined $padding ) { $padding = '5'; }

    $brickcount++;

    my $brick_r = Cpanel::Template::process_template(
        'whostmgr',
        {
            'print'         => 0,
            'template_file' => 'brickstart.tmpl',
            'brickalign'    => $align,
            'brickpadding'  => $padding,
            'brickpercent'  => $percent,
            'bricktitle'    => $title,
        },
    );

    require Whostmgr::HTMLInterface::Output;
    Whostmgr::HTMLInterface::Output::print2anyoutput( ${$brick_r} );

    return;
}

sub brickend {
    my $brick_r = Cpanel::Template::process_template(
        'whostmgr',
        {
            'print'         => 0,
            'template_file' => 'brickend.tmpl',
        },
    );

    require Whostmgr::HTMLInterface::Output;
    Whostmgr::HTMLInterface::Output::print2anyoutput( ${$brick_r} );

    return;
}

sub htmlexec {
    require Whostmgr::HTMLInterface::Exec;
    goto &Whostmgr::HTMLInterface::Exec::htmlexec;
}

sub print_results_message {

    Cpanel::Template::process_template(
        'whostmgr',
        {
            'template_file' => 'print_results_message.tmpl',
            'data'          => shift(),
        }
    );

    return;
}

sub load_statusbox {
    my $appname = shift;
    return if ( -t STDOUT || !defined $ENV{'GATEWAY_INTERFACE'} || $ENV{'GATEWAY_INTERFACE'} !~ m/CGI/i );
    local $Cpanel::App::appname = 'whostmgr';    #make sure we get the right magic revision module
    load_css('/yui/container/assets/container.css');
    load_js('/js/statusbox.js');
    print qq{<div id=sdiv></div>};
    print qq{<script>whmappname='$appname';</script>};
    print qq{ } x 4096;
    print "\n";

    return 1;
}

sub load_js {
    my $script = shift;
    if ( exists $LOADED{$script} ) { return; }
    $LOADED{$script} = 1;
    local $Cpanel::App::appname = 'whostmgr';    #make sure we get the right magic revision module

    require Cpanel::MagicRevision;
    print qq{<script type="text/javascript" src="} . Cpanel::MagicRevision::calculate_magic_url($script) . qq{"></script>\n};
    return 1;
}

sub load_css {
    my $css = shift;
    if ( exists $LOADED{$css} ) { return; }
    $LOADED{$css} = 1;
    local $Cpanel::App::appname = 'whostmgr';    #make sure we get the right magic revision module
    require Cpanel::MagicRevision;
    print qq{<link rel="stylesheet" type="text/css" href="} . Cpanel::MagicRevision::calculate_magic_url($css) . qq{" />};

    return 1;
}

sub jsscrollend {
    return if $DISABLE_JSSCROLL;

    my $jscode = '<script>
     function scrollend() {
         var scrollEnd;
         if (window.scrollHeight) {
            scrollEnd=window.scrollHeight;
         } else if (document.body.scrollHeight) {
            scrollEnd=document.body.scrollHeight;
         } else {
            scrollEnd=100000000;
         }
         window.scroll(0,scrollEnd);
     }
     </script>';

    my $on_a_tty = -t STDIN && -t STDOUT;
    if ( !$printed_jsscrollend ) {
        syswrite( STDOUT, $jscode ) if !$on_a_tty;    #no buffering
        $printed_jsscrollend = 1;
    }
    syswrite( STDOUT, '<script>window.setTimeout(scrollend,180);</script>' ) if !$on_a_tty;    #no buffering
    return;
}

sub sendfooter {
    my $prog = shift;

    return             if $sentdeffooter;
    return deffooter() if $sentdefheader && !$sentdeffooter;

    if ( $prog !~ /(?:wml|remote_|getlangkey|addpkg|editpkg|killpkg|killacct|showversion|wwwacct|gethostname)/ ) {    # for cPanel::PublicAPI compat see CPANEL-876
        print qq{<!-- Web Host Manager } . Cpanel::Version::Full::getversion() . qq{ [$Whostmgr::Session::binary] (c) cPanel, L.L.C. $copyright
            http://cpanel.net/  Unauthorized copying is prohibited -->\n};
    }

    return;
}

sub redirect {
    my ($uri) = @_;

    my $json_uri = Cpanel::JSON::Dump($uri);

    print <<EOM;

<script type="text/javascript">window.location.href=$json_uri;</script>

EOM
    return;
}

#legacy, unneeded
sub js_security_token { return q{} }

1;
