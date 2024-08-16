#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - whostmgr/docroot/cgi/cpaddons.pl        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 DESCRIPTION

Manage cPanel&WHM cPaddons

We have B<deprecated> this interface in cPanel & WHM version 104 and plan to remove it in future versions.
For more information, read our L<cPanel Deprecation Plan|https://docs.cpanel.net/knowledge-base/cpanel-product/cpanel-deprecation-plan/>
documentation.

=head1 Functions

=cut

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings) -- This file is not warnings-safe.

BEGIN { unshift @INC, '/usr/local/cpanel', '/usr/local/cpanel/whostmgr/docroot/cgi', '/usr/local/cpanel/cpaddons'; }

use CGI;
use IPC::Open3 ();
use Carp       ();

use Time::HiRes ();
my $debug      = CGI::param('debug') ? 1 : 0;
my $start_page = [ Time::HiRes::gettimeofday() ] if $debug;

use Cpanel::Config::Sources        ();
use Cpanel::cPAddons::Filter       ();
use Cpanel::cPAddons::LegacyNaming ();
use Cpanel::OS                     ();
use Cpanel::SafeRun::Simple        ();
use Cpanel::Server::Type           ();
use Cpanel::Encoder::Tiny          ();
use Cpanel::HttpRequest            ();
use Cpanel::PipeHandler            ();
use Cpanel::StringFunc::Match      ();
use Cpanel::StringFunc::Trim       ();
use Cpanel::Template               ();
use Whostmgr::ACLS                 ();
use Whostmgr::Cpaddon::Conf        ();
use Whostmgr::Cpaddon::Signatures  ();
use Whostmgr::Addons::Manager      ();

if ( !Cpanel::OS::supports_cpaddons() || -e q[/var/cpanel/cpaddons.disabled] ) {
    my $msg = "cPAddons are disabled on this server";
    if ( !-t STDIN ) {
        print "Content-type: text/html\r\n\r\n";
        print_header();
        print div_warning($msg);
    }
    else {
        print $msg;
    }
    exit 0;
}

chdir('/usr/local/cpanel') || die "Could not chdir /usr/local/cpanel: $!";

# CGI::param called in list context can lead to vulnerabilities.
#   http://blog.gerv.net/2014.10/new-class-of-vulnerability-in-perl-web-applications
# We are not using the list to populate a hash, disable the warning
$CGI::LIST_CONTEXT_WARN = $CGI::LIST_CONTEXT_WARN = 0;    # no warnings once

local $| = 1;

my $action = CGI::param('action');
my $nohtml;

# The nohtml flag is currently only supported on the update action.

if ( $action eq 'update-nohtml' ) {
    $action = 'update';
    $nohtml = 1;
}

my ( $br, $output_handler );

my $TEMPLATE_DIRECTORY   = 'cpaddons/partials';
my $TEMPLATE_APPLICATION = 'whostmgr';

if ($nohtml) {
    if ( !-t STDIN ) {
        print "Content-type: text/plain\r\n\r\n";
    }

    $br = "\n";
    require Cpanel::Output::Template;
    $output_handler = Cpanel::Output::Template->new(
        template_directory => $TEMPLATE_DIRECTORY . "/text",
        template_extension => '.tmpl',
        application        => $TEMPLATE_APPLICATION,
        break              => $br,
    );

    require Cpanel::Output::Formatted::Terminal;
    $Cpanel::SysPkgs::OUTPUT_OBJ_SINGLETON = Cpanel::Output::Formatted::Terminal->new();

}
else {
    print "Content-type: text/html\r\n\r\n";
    print_header();

    $br = "<br />\n";
    require Cpanel::Output::Template;
    $output_handler = Cpanel::Output::Template->new(
        template_directory => $TEMPLATE_DIRECTORY . "/html",
        template_extension => '.tmpl',
        application        => $TEMPLATE_APPLICATION,
        break              => $br,
        expand_linefeeds   => 1,
    );

    # Setup the output formatter for the YUM system.
    require Cpanel::Output::Formatted::HTML;
    $Cpanel::SysPkgs::OUTPUT_OBJ_SINGLETON = Cpanel::Output::Formatted::HTML->new();
}

#Allows mainCommand features to display in left nav. To ensure that ACL init happens for all the pages that use _defheader so that Left navigation and ACL checks work.
Whostmgr::ACLS::init_acls();

if ( !Whostmgr::ACLS::hasroot() ) {
    if ( !-t STDIN && !$nohtml ) {
        print_output( 'Permission denied', 'error', 'permission-denied-error' );
        print_footer();
    }
    exit;
}
elsif ( $> != 0 ) {
    exit;
}

my $force = CGI::param('force');

if ( Cpanel::Server::Type::is_dnsonly() ) {
    print_output( 'This feature is disabled for DNSONLY servers.', 'error', 'dns-only-error' );
    print_footer();
    exit;
}

local $SIG{'PIPE'} = \&Cpanel::PipeHandler::pipeBGMgr;

my ( $Availab, $Current, $OwnVend ) = _handle_exception_as_html(
    sub {
        Whostmgr::Cpaddon::Conf::load( force => $force );
    }
);

my $load_duration = Time::HiRes::tv_interval($start_page) if $debug;

if ( $action eq 'upvend' ) {
    print "<h3>Updating vendor config …</h3>\n";
    my $there_were_changes = 0;
  VENDORLOOP:
    for my $vndinf ( CGI::param('vndinf') ) {
        next if !$vndinf;
        my $name = _get_url( $vndinf, '' );
        if ( $name =~ m{cPanel}i ) {

            # Someone is trying to fool you
            print "<p>3rd party vendor may be attempting to masquerade as cPanel, skipping vendor …</p>\n";
            next;
        }

        if ( $name && $name =~ m/^\w+$/ ) {

            my $htmlsafe_name = CGI::escapeHTML($name);

            if ( !exists $OwnVend->{$name} ) {
                my $cphost = _get_url( $vndinf, 'cphost=1' );
                my $cphuri = _get_url( $vndinf, 'cphuri=1' );
                my $palmd5 = _get_url( $vndinf, 'palmd5=1' );

                $cphuri = "/$cphuri" if !Cpanel::StringFunc::Match::beginmatch( $cphuri, '/' );
                $cphuri = Cpanel::StringFunc::Trim::endtrim( $cphuri, '/' );

                if ( $cphost && $cphuri && $palmd5 ) {    # we already know $name is ok
                    print qq(Adding Vendor $htmlsafe_name to your config …<br />\n);
                    $OwnVend->{$name} = {
                        'vndinf' => $vndinf,
                        'cphost' => $cphost,
                        'cphuri' => $cphuri,
                        'palmd5' => $palmd5,
                    };

                    eval {

                        Cpanel::HttpRequest->new( hideOutput => 1 )->request(
                            'host'     => $OwnVend->{$name}->{'cphost'},
                            'url'      => "$OwnVend->{$name}->{'cphuri'}/cPAddonsAvailable/$name.pm",
                            'destfile' => "/usr/local/cpanel/cpaddons/cPAddonsAvailable/$name.pm",
                            Whostmgr::Cpaddon::Signatures::httprequest_sig_flags($name)
                        );

                        Cpanel::HttpRequest->new( hideOutput => 1 )->request(
                            'host'     => $OwnVend->{$name}->{'cphost'},
                            'url'      => "$OwnVend->{$name}->{'cphuri'}/cPAddonsMD5/$name.pm",
                            'destfile' => "/usr/local/cpanel/cpaddons/cPAddonsMD5/$name.pm",
                            Whostmgr::Cpaddon::Signatures::httprequest_sig_flags($name)
                        );
                    };
                    if ($@) {
                        print "Failed to fetch vendor modules for '$htmlsafe_name'<br />\n" . CGI::escapeHTML($@);
                        next VENDORLOOP;
                    }

                    my @check = ( "/usr/local/cpanel/cpaddons/cPAddonsMD5/$name.pm", "/usr/local/cpanel/cpaddons/cPAddonsAvailable/$name.pm" );
                    for my $pm (@check) {
                        if ( !_perl_c($pm) ) {
                            my $safe = CGI::escapeHTML($vndinf);
                            print "Url &quot;$safe&quot; did not work or was otherwise invalid.<br />\n";    # same error used elsewhere, will get updated properly in 2.0
                            unlink @check;
                            last;
                        }
                    }

                    $there_were_changes++;
                }
            }
            else {
                print "The vendor $htmlsafe_name is already in your configuration.<br />\n";
            }
        }
        else {
            my $safe = CGI::escapeHTML($vndinf);
            print "Url &quot;$safe&quot; did not work or was otherwise invalid.<br />\n";
        }
    }

    for ( CGI::param('remove') ) {
        my $escaped = CGI::escapeHTML($_);
        print "Removing $escaped from your list …<br />\n";
        $there_were_changes++;
        delete $OwnVend->{$_};
    }

    _handle_exception_as_html( sub { Whostmgr::Cpaddon::Conf::write_conf() } ) if $there_were_changes;
    print qq(<p>[<a href="$ENV{SCRIPT_NAME}?">Back</a>]</p>\n);
    print_footer();
}
elsif ( $action eq 'rmpm' ) {
    my $mod     = CGI::param('mod');
    my $manager = Whostmgr::Addons::Manager->new(

        # Flags
        debug => $debug,

        # Delegated operations
        notify_fn => \&print_output,
    );
    print '<div id="processing">' . "\n";
    $manager->purge($mod);
    print '</div>' . "\n";

    my $exp_debug = $debug ? "debug=1" : "";
    print qq(<p>[<a href="$ENV{'SCRIPT_NAME'}?$exp_debug">Back</a>]</p>\n);
}
elsif ( $action eq 'update' ) {

    # Factor out handling of html/non-html into one string and one function. The only reason
    # for using an anonymous sub here was to keep the format close to the place it is used.

    print '<div id="processing">' . "\n";
    print_output( "Updating Local Addons Database …", 'line' );

    my $basesyncdir = '/cpanelsync/cpaddons';                     # no trailing slash
    my %CPSRC       = Cpanel::Config::Sources::loadcpsources();

    _cpanelsync(
        Whostmgr::Cpaddon::Signatures::cpanelsync_sig_flags('cPanel'),
        $CPSRC{'HTTPUPDATE'},
        "$basesyncdir/cPAddonsMD5",
        '/usr/local/cpanel/cpaddons/cPAddonsMD5',
    );

    for my $vnd ( keys %$OwnVend ) {
        next if !$vnd;
        eval { Cpanel::HttpRequest->new( 'htmlOutput' => 1 )->request( 'host' => $OwnVend->{$vnd}->{'cphost'}, 'url' => "$OwnVend->{$vnd}->{'cphuri'}/cPAddonsMD5/$vnd.pm", 'destfile' => "/usr/local/cpanel/cpaddons/cPAddonsMD5/$vnd.pm", Whostmgr::Cpaddon::Signatures::httprequest_sig_flags($vnd) ); };

        eval "use cPAddonsMD5\:\:$vnd;";    ##no critic(ProhibitStringyEval)
        unlink "/usr/local/cpanel/cpaddons/cPAddonsMD5/$vnd.pm" if $@;
    }

    my $config_definitions = {};
    print "$br\n";

    my $force = CGI::param('force');
    for my $amod ( sort keys %$Availab ) {

        # Unify the vendors
        require Cpanel::SafeStorable;
        my $vendors = Cpanel::SafeStorable::dclone($OwnVend);
        $vendors->{'cPanel'} = {
            cphost => $CPSRC{HTTPUPDATE},
            cphuri => $basesyncdir,
        };

        my $manager = Whostmgr::Addons::Manager->new(
            CURRENT_MODULES   => $Current,
            AVAILABLE_MODULES => $Availab,
            VENDORS           => $vendors,

            # Flags
            debug      => $debug,
            htmlOutput => 1,

            # Delegated operations
            notify_fn      => \&print_output,
            sync_cpanel_fn => \&_cpanelsync,
            check_perl_fn  => \&_perl_c,
        );

        if ( CGI::param($amod) ) {
            $config_definitions->{$amod} = $manager->install( $amod, $force );
        }
        else {
            $config_definitions->{$amod} = $manager->uninstall( $amod, $force );
        }
    }

    print '</div>' . "\n";

    _handle_exception_as_html(
        sub {
            Whostmgr::Cpaddon::Conf::write_conf( config_definitions => $config_definitions );
        }
    );

    my $exp_debug = $debug ? "debug=1" : "";
    print qq(<p>[<a href="$ENV{'SCRIPT_NAME'}?$exp_debug">Back</a>]</p>\n) unless $nohtml;

    print_footer() unless $nohtml;

    # refresh the touch flag to disable cpaddons when removing the last one
    Cpanel::SafeRun::Simple::saferunnoerror( $^X, "/usr/local/cpanel/install/CheckCpAddons.pm" );

}
elsif ( $action eq 'showsecurity' ) {
    my $mod        = CGI::param('addon') || return;
    my @components = grep { !tr/A-Za-z0-9_//c } split /::/, $mod;
    exit unless scalar(@components) == 3;
    my ( $vend, $cat, $name ) = @components;
    exit unless -e "/usr/local/cpanel/cpaddons/$vend/$cat/$name.pm";
    require "/usr/local/cpanel/cpaddons/$vend/$cat/$name.pm";
    no strict 'refs';
    my $security =
         $vend eq 'cPanel'
      && defined ${"$vend\:\:$cat\:\:$name\:\:meta_info"}
      && exists ${"$vend\:\:$cat\:\:$name\:\:meta_info"}->{'security'} ? ${"$vend\:\:$cat\:\:$name\:\:meta_info"}->{'security'} : 'No information available';

    print qq{
        <h4>${\CGI::escapeHTML($mod)}</h4>
        <div>
            <table width="90%">
                <tr>
                    <td>${\CGI::escapeHTML($security)}</td>
                </tr>
            </table>
        </div>
    };
    print_footer();
    exit;
}
else {
    # Show the list of addons available/installed

    _handle_exception_as_html( sub { Whostmgr::Cpaddon::Conf::write_conf( force => 1, if_missing => 1 ) } );

    my $deprecation_warning = div_warning( <<EOS );
    We have <b>deprecated</b> this interface in cPanel & WHM version 104 and plan to remove it in future versions.
    For more information, read our <a href="https://docs.cpanel.net/knowledge-base/cpanel-product/cpanel-deprecation-plan/" target="_blank">cPanel Deprecation Plan</a> documentation.
EOS

    print qq[<div class="col-xs-12 col-sm-12 col-md-8 col-lg-6">
    $deprecation_warning
    </div>];

    my $needs_notices = 0;
    for my $app ( sort keys %$Availab ) {
        my ( $vend, $cat, $name ) = split /\:\:/, $app;
        my $has_pm        = -e "/usr/local/cpanel/cpaddons/$vend/$cat/$name.pm";
        my $is_deprecated = Cpanel::cPAddons::Filter::is_deprecated($app);
        my $is_installed  = $Current->{$app}->{'VERSION'} ? 1 : 0;
        if ( $is_deprecated && ( $is_installed || $has_pm ) ) {
            $needs_notices = 1;
            last;    # We only care if at least one is needed.
        }
    }

    my $notice_header = $needs_notices ? "<th>Notices</th>\n" : "";
    print qq{
    <div class="row">
        <div class="col-xs-12 col-sm-12 col-md-9 col-lg-8">
            <form action="$ENV{'SCRIPT_NAME'}" method="post">
                <input type="hidden" name="action" value="update" />

                <table id="addon-list"
                       class="table table-striped table-condensed"
                       summary="Available cPAddons Site Software Installations">
                    <tr>
                        <th>Installed</th>
                        <th>Vendor</th>
                        <th>Category</th>
                        <th>Name</th>
                        <th>Version</th>
                        $notice_header
                    </tr>
        };
    my $do_pm_warn = 0;

    for my $app ( sort keys %$Availab ) {
        my ( $vend, $cat, $name ) = split /\:\:/, $app;
        my $has_pm  = -e "/usr/local/cpanel/cpaddons/$vend/$cat/$name.pm";
        my $has_lib = -d "/usr/local/cpanel/cpaddons/$vend/$cat/$name/";

        # Do not list the addon if it is blacklisted
        next if Cpanel::cPAddons::Filter::is_blacklisted($app);

        my $is_deprecated = Cpanel::cPAddons::Filter::is_deprecated($app);
        my $is_installed  = $Current->{$app}->{'VERSION'} ? 1 : 0;

        my $checked  = $Current->{$app}->{'VERSION'}                    ? ' checked="checked"'   : '';
        my $disabled = $is_deprecated && !$Current->{$app}->{'VERSION'} ? ' disabled="disabled"' : '';

        # Do not list the addon if its not installed and has been deprecatated
        if ( !$Current->{$app}->{'VERSION'} && $is_deprecated ) {
            my $is_rpm = !!$Availab->{$app}{package}{rpm_name};
            next if $is_rpm;
            next if !$has_lib && !$has_pm;    # Legacy addons supported a limbo state where you can't install, but existing installs are still usable.
        }

        my $unpmfile = !$has_lib && $has_pm
          ? qq(
                    <a href="$ENV{'SCRIPT_NAME'}?action=rmpm&mod=$app">
                        Completely Remove
                    </a> **
                )
          : '';

        my $pm_bad;
        if ( -e "/usr/local/cpanel/cpaddons/$vend/$cat/$name.pm" ) {
            $pm_bad = not eval {
                require "/usr/local/cpanel/cpaddons/$vend/$cat/$name.pm";
                1;
            };
        }

        $do_pm_warn++ if $unpmfile;
        $cat =~ s/\_/ /g;
        $vend = ( $vend eq 'cPanel' ) ? "cPanel, L.L.C." : $vend;

        my $display_app_name = Cpanel::cPAddons::LegacyNaming::get_app_name($app);

        my $deprecated_warning = '';
        if ($is_deprecated) {
            my $warning = ' ' . ( $has_lib ? "If the application is uninstalled it can not be reinstalled." : "If the application is completely removed, it can not be reinstalled." );
            my $id      = $app . "-legacy-warning";
            $deprecated_warning = div_warning( "This application is deprecated.$warning", $id );
        }

        my $notice_column = $needs_notices ? "<td>$deprecated_warning</td>\n" : "";
        print qq(
            <tr>
                <td class="center">
                    <span class="checkbox">
                        <input type="checkbox" name="$app" value="1"$checked$disabled />
                    </span>
                </td>
                <td>$vend</td>
                <td>$cat</td>
                <td>$display_app_name</td>
                <td><span class="text-nowrap">$Availab->{$app}->{'version'}$unpmfile</span></td>
                $notice_column
            </tr>
        );

        if ($pm_bad) {
            print qq(
                <tr>
                    <td></td>
                    <td colspan="4" class="error">
                        Error loading $display_app_name: $@
                    </td>
                </tr>
            );
        }
    }

    print qq{
                <tr>
                    <td class="center">
                        <span class="checkbox">
                            <input type="checkbox" name="force" value="1" />
                        </span>
                    </td>
                    <td align="left" colspan="4">
                        Force Refresh of All cPAddons Site Software Sources
                    </td>
                </tr>
            </table>
            <input type="submit" value="Update cPAddon Config" class="btn btn-primary" id="btn-update-cpaddon-config" />
            <input type="hidden" name="debug" id="debug" value="$debug">
        </form>
    </div>
</div>
    };

    my $package_warning_msg = qq[<b>**</b> You should only completely remove the package if you have <a target="_blank" href="cpaddons_report.pl">uninstalled all cPAddons Site Software</a> first. Otherwise, you cannot remove the ophaned installations until you reinstall the module.];
    my $package_warning_div = div_warning( $package_warning_msg, 'completely-remove-warning' );

    print qq{
<br/>
<div class="row">
    <div class="col-xs-12 col-sm-12 col-md-8 col-lg-6">
        $package_warning_div
    </div>
</div>
    } if $do_pm_warn;

    my $div_warning_3rd_party = div_warning("This feature allows installation of 3rd party cPAddons Site Software packages that cPanel, L.L.C. does not provide.");

    # Build the add vendors form
    print qq(
    <div class="row">
        <div class="col-xs-12 col-sm-12 col-md-8 col-lg-6">
            <h3>Add or Remove Vendors</h3>
            $div_warning_3rd_party
    );
    my $vndinf     = CGI::escapeHTML( CGI::param('vndinf') );
    my $vendorlist = '';
    for my $vnd ( sort keys %$OwnVend ) {
        next if !$vnd;
        next if ref $OwnVend->{$vnd} ne 'HASH';
        next if !keys %{ $OwnVend->{$vnd} };
        $vendorlist .= qq(
        <tr>
            <td>$vnd</td>
            <td class="right">
                <span class="checkbox">
                    <input type="checkbox" name="remove" value="$vnd" />
                </span>
            </td>
        </tr>
        );
    }

    $vendorlist = qq(
        <tr>
            <th>Vendor</th>
            <th>Remove</th>
        </tr>
        $vendorlist
    ) if $vendorlist;

    my $url_count  = int CGI::param('url_count') && int CGI::param('url_count') < 15 ? int CGI::param('url_count') : 1;
    my $url_fields = qq(
        <tr>
            <td>URL:</td>
            <td>
                <input type="text" name="vndinf" size="40" value="$vndinf" class="form-control" />
            </td>
        </tr>
    ) x $url_count;

    print <<"ADD_END";
        <form action="$ENV{SCRIPT_NAME}" method="post">
            <input type="hidden" name="action" value="upvend" />
            <table class="table table-striped table-condensed">
                $vendorlist
                <tr>
                    <td colspan="2">Vendor's information URL:</td>
                </tr>
                $url_fields
                <tr>
                    <td>&nbsp;</td>
                    <td>
                        <input type="submit" value="Update Vendors" class="btn btn-primary" />
                    </td>
                </tr>
            </table>
            <input type="hidden" name="debug" id="debug" value="$debug">
        </form>

        <form action="$ENV{SCRIPT_NAME}" method="post" class="form-inline">
            <table>
                <tr>
                    <td colspan="2">Add additional vendor URL fields:</td>
                </tr>
                <tr>
                    <td colspan="2">
                        <!-- TODO: Remove this silly text field expansion -->
                        <select name="url_count" class="form-control">
                            <option selected value="1">1</option>
                            <option value="2">2</option>
                            <option value="3">3</option>
                            <option value="4">4</option>
                            <option value="5">5</option>
                            <option value="6">6</option>
                            <option value="7">7</option>
                            <option value="8">8</option>
                            <option value="9">9</option>
                            <option value="10">10</option>
                            <option value="11">11</option>
                            <option value="12">12</option>
                            <option value="13">13</option>
                            <option value="14">14</option>
                        </select>
                        <input type="submit" value="Add additional URL fields" class="btn btn-primary" />
                    </td>
                </tr>
            </table>
            <input type="hidden" name="debug" id="debug" value="$debug">
        </form>
    </div>
</div>
<br/>
ADD_END
    print_footer();
}

print_performance() if $debug;

# TODO: Need to print a std-footer as the page is never really finished

sub print_performance {
    my $page_duration   = Time::HiRes::tv_interval($start_page);
    my $render_duration = $page_duration - $load_duration;
    print qq{
        whole page:  $page_duration<br/>
        render only: $render_duration<br/>
    };
    return;
}

sub _get_url {
    my ( $url, $get ) = @_;

    # Cpanel::HttpRequest does not allow for assigning to anything but a file, so we:
    require LWP::UserAgent;

    my $ua = LWP::UserAgent->new;
    $ua->timeout(10);

    my $res = $ua->get( $get ? "$url?$get" : $url );
    return $res->is_success() ? $res->content() : '';    # return content or empty string
}

# TODO: Move to a module, where?
sub _perl_c {
    my ($file) = @_;
    return if !defined $file || $file eq '';

    # string context so that the '>/dev/null 2>&1' will work
    return system( '/usr/local/cpanel/3rdparty/bin/perl -c ' . quotemeta($file) . ' >/dev/null 2>&1' ) == 0 ? 1 : 0;
}

sub _cpanelsync {
    my @arguments = @_;

    my $out_fh;
    my $buf = '';
    my $pid = IPC::Open3::open3( undef, $out_fh, $out_fh, '/usr/local/cpanel/scripts/cpanelsync', @arguments );

    while ( sysread( $out_fh, $buf, 1024 ) ) {
        $buf = Cpanel::Encoder::Tiny::safe_html_encode_str($buf);
        $buf =~ s{\n}{<br />\n}g unless $nohtml;
        print $buf;
    }

    waitpid( $pid, 0 );

    return $? ? 0 : 1;
}

sub print_header {
    Cpanel::Template::process_template(
        'whostmgr',
        {
            'print'                      => 1,
            'template_file'              => 'master_templates/_defheader.tmpl',
            'theme'                      => 'bootstrap',
            'app_key'                    => 'install_cpaddons_site_software',
            'include_legacy_stylesheets' => 1,
            'extrastyle'                 => qq(
                .table td.center input { margin-left: auto; margin-right: auto }
                .table td.right input { float: right }
                .text-nowrap { white-space: nowrap; }
                .whm-app-title__image{width:48px;height:48px}
                #addon-list {min-width: 600px; }
                #addon-list .alert { margin-bottom: 0; max-width: 400px; }
                #processing .alert { margin-bottom: 10px; margin-top: 5px; max-width: 1024px; }
                #processing p { margin-bottom: 15px }
            ),
        },
    );
    return;
}

sub print_footer {
    Cpanel::Template::process_template(
        'whostmgr',
        {
            'print'                      => 1,
            'template_file'              => 'master_templates/_deffooter.tmpl',
            'theme'                      => 'bootstrap',
            'include_legacy_stylesheets' => 1,
            'skipsupport'                => 1,
        },
    );
    return;
}

=pod

=head2 div_warning( $msg, $id = '' )

Returns an html '<div>' warning to display the message C<$msg>.
Optionally can set the div id by providing C<$id>.

=cut

sub div_warning {
    my ( $msg, $id ) = @_;

    return '' unless length $msg;
    $id //= '';

    return <<"EOS";
    <div class="alert alert-warning">
        <span class="glyphicon glyphicon-exclamation-sign"></span>
        <div class="alert-message" id="$id">
        <strong>Warning:</strong>
        $msg
        </div>
    </div>
EOS

}

sub _handle_exception_as_html {
    my ($func) = @_;

    my $context = wantarray();
    if ( !$context && defined($context) ) {
        Carp::croak('Defect: _handle_exception_as_html called in scalar context. Please use list or void.');    # scalar will cause the function to mishandle the return due to the use of an array
    }

    my @result = eval { $func->() };
    if ( my $exception = $@ ) {
        my ( $success, $output ) = Cpanel::Template::process_template(
            'whostmgr',
            {
                template_file => '/usr/local/cpanel/whostmgr/docroot/templates/cpaddons/exception.tmpl',
                data          => { exception => $exception },
            }
        );
        print $$output;
        exit;
    }
    return @result;
}

sub print_output {
    my ( $message, $type, $id, $classes ) = @_;

    # Expand any internal linefeeds
    $message =~ s/\n/$br/g;
    return $output_handler->message( $type, $message, $id, undef, $classes );
}
