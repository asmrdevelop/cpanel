#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - whostmgr/docroot/cgi/cpaddons_report.pl Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

## no critic qw(RequireUseWarnings)
use strict;

BEGIN { unshift @INC, '/usr/local/cpanel', '/usr/local/cpanel/whostmgr/docroot/cgi', '/usr/local/cpanel/cpaddons'; }

use Cpanel;
use Cpanel::AccessIds                    ();
use Cpanel::AccessIds::ReducedPrivileges ();
use Cpanel::Config::Users                ();
use Cpanel::Config::LoadCpConf           ();
use Cpanel::ContactInfo                  ();
use Cpanel::ContactInfo::Email           ();
use Cpanel::Encoder::URI                 ();
use Cpanel::PwCache                      ();
use Cpanel::PwCache::Build               ();
use Cpanel::SafeDir::MK                  ();
use Cpanel::Server::Type                 ();
use Cpanel::Sys::Hostname                ();
use Cpanel::Template                     ();
use Cpanel::Validate::EmailRFC           ();
use Cpanel::cPAddons::Cache              ();
use Cpanel::cPAddons::Filter             ();
use Cpanel::cPAddons::LegacyNaming       ();
use Cpanel::cPAddons;
use Cpanel::OS     ();
use Whostmgr::ACLS ();

Whostmgr::ACLS::init_acls();

exit unless Cpanel::OS::supports_cpaddons();

my $notify     = defined $ARGV[0] && $ARGV[0] eq '--notify' ? 1 : 0;
my $html       = -t STDIN || $notify                        ? 0 : 1;
my %cpconf     = Cpanel::Config::LoadCpConf::loadcpconf();    # we want a copy not a reference since initcp() will clear it
my $cpconf_ref = \%cpconf;                                    # we want a copy not a reference since initcp() will clear it

if ( $notify && $cpconf_ref->{'cpaddons_autoupdate'} ) {
    require Cpanel::SafeRun::Errors;
    Cpanel::SafeRun::Errors::saferunallerrors( '/usr/local/cpanel/scripts/cpaddonsup', '--force', ( $html ? '--html' : '--nohtml' ) );
}

if ($html) {
    print "Content-type: text/html\r\n\r\n";
    print_header();
    if ( !Whostmgr::ACLS::hasroot() ) {
        print <<'EOM';
    <div class="alert alert-danger">
        <span class="glyphicon glyphicon-remove-sign"></span>
        <div class="alert-message" id="permission-denied-error">
            <strong>Error:</strong>
            Permission denied.
        </div>
    </div>
EOM
        print_footer();
        exit;
    }

    if ( Cpanel::Server::Type::is_dnsonly() ) {
        print <<'EOM';
    <div class="alert alert-danger">
        <span class="glyphicon glyphicon-remove-sign"></span>
        <div class="alert-message" id="dns-only-error">
            <strong>Error:</strong>
            This feature is disabled for DNSONLY servers.
        </div>
    </div>
EOM
        print_footer();
        exit;
    }
}
elsif ( $> != 0 ) {
    print_footer();
    exit;
}

sub hasfeature { goto &Cpanel::hasfeature; }

{
    local $@;
    eval 'use cPAddonsConf';    ## no critic qw(ProhibitStringyEval) -- I'm not interested in refactoring this
    if ($@) {
        my $err_str = "Please create a cPAddons Site Software Configuration";
        if ($html) {
            print "<h3 class=\"errors\">$err_str <a href=\"cpaddons.pl?force=1\">here</a></h3>\n";
            print_footer();
        }
        elsif ( !$notify ) {
            print "$err_str\n";
        }
        exit;
    }
}

Cpanel::PwCache::Build::init_passwdless_pwcache();

use CGI;
use Carp;

delete $ENV{'REMOTE_PASSWORD'};

my $hostname = Cpanel::Sys::Hostname::gethostname();

my $user = CGI::param('user');

my %HOMES;
my @USERS = Cpanel::Config::Users::getcpusers();

if ($user) {
    $HOMES{$user} = Cpanel::PwCache::gethomedir($user) || die "Could not determine homedir for user:[$user]";
    $USERS[0] = $user;
}
else {
    Cpanel::PwCache::Build::init_passwdless_pwcache();
    my $pwcache_ref = Cpanel::PwCache::Build::fetch_pwcache();
    %HOMES = map { $_->[0] => $_->[7] } @{$pwcache_ref};
}

my ($admincontactemail) = exists $cpconf_ref->{'cpaddons_adminemail'} && $cpconf_ref->{'cpaddons_adminemail'} ? $cpconf_ref->{'cpaddons_adminemail'} : "cpanel\@$hostname";
$admincontactemail = ( Cpanel::ContactInfo::Email::split_multi_email_string($admincontactemail) )[0];

my $back           = '';
my $security_token = $ENV{'cp_security_token'} || '';

my $multi = do_action();

if ( !defined $user && $html ) {
    print _moderation_view_reqs_link();
    print _print_actions( \@USERS );
    print _moderation_hash_form();
    print_footer();
    exit;
}

$user = $ARGV[0] || '' if !$user;

my $dump = CGI::param('dumpreg');
if ( $dump && $user ) {

    # Gather the data
    Cpanel::initcp($user);
    $Cpanel::homedir = $HOMES{$user} || die "Could not determine homedir for user:[$user]";
    my $path = "$Cpanel::homedir/.cpaddons/$dump";
    my $hr   = {};
    Cpanel::cPAddons::Cache::read_cache( $path, $hr, $user );

    # Output the data
    require Data::Dumper;
    1 or $Data::Dumper::Sortkeys or die;
    local $Data::Dumper::Sortkeys = 1;
    my $printable_path = CGI::escapeHTML($path);
    my $data_html      = CGI::escapeHTML( Data::Dumper::Dumper($hr) );
    $data_html =~ s/\$VAR1 =//;
    print qq{
        <b>Registry Info for $printable_path</b>
        <pre>
        $data_html
        </pre>
    };
    print_footer();
    exit;
}

my $show = scalar CGI::param('show') || '';

if ( grep /^\Q$user\E$/, @USERS ) {
    @USERS = ($user);
    if ($html) {
        print qq(
            <p>
                <b>Current User:</b> ${\_html($user)}
                [ <a href="$ENV{'SCRIPT_NAME'}?show=${\_uri($show)}&user=">View All Users</a> ]
            </p>
        );
    }
}

if ($html) {
    print qq(<p><b><a href="$ENV{'SCRIPT_NAME'}?">Main Page</a></b></p>\n);    # the  "?" is not a mistake
    if ( $show eq 'up' || $show eq 'in' ) {
        print qq(<p><a href="$ENV{'SCRIPT_NAME'}?show=&user=${\_uri($user)}">Show all installs</a></p>\n);
        print qq(<p><a href="$ENV{'SCRIPT_NAME'}?show=up&user=${\_uri($user)}">Show all installs that need updated</a></p>\n)
          if $show ne 'up';
        print qq(<p><a href="$ENV{'SCRIPT_NAME'}?show=in&user=${\_uri($user)}">Show all installs that are no longer installed in WHM</a></p>\n)
          if $show ne 'in';
    }
    else {
        $show = '';
        print <<SHW;
            <p><a href="$ENV{'SCRIPT_NAME'}?show=up&user=${\_uri($user)}">Show all installs that need updated</a></p>
            <p><a href="$ENV{'SCRIPT_NAME'}?show=in&user=${\_uri($user)}">Show all installs that are no longer installed in WHM</a></p>
SHW
    }
}

my $has_installs = 0;
print $html
  ? qq( <style>td { padding-left: 3px; padding-right: 3px; }</style>
        <table>
        <tr class="scellheader">
            <td>User</td>
            <td>Addon</td>
            <td>Latest</td>
            <td>Version</td>
            <td><a href="cpaddons.pl">Currently installed in WHM</a></td>
        </tr>)
  : ''
  if !$multi;

my $tdshade = 'tdshade2';

my %cpaddoninfo;
my %installedx = %cPAddonsConf::inst;

my %reseller_acls;
if ($notify) {
    require Cpanel::Reseller;
    %reseller_acls = Cpanel::Reseller::getresellersaclhash();
}

my %owner_emails;
USR:
for my $usr ( sort @USERS ) {

    # Legacy compat
    my $user_homedir = $HOMES{$usr} || die "Could not determine homedir for user:[$usr]";

    next if !-d "$user_homedir/.cpaddons/";
    my $needsupdated = '';

    if ( opendir REG, "$user_homedir/.cpaddons/" ) {
        my @installed = grep /\A(?:[A-Za-z0-9_]+::){2}[A-Za-z0-9_]+\.\d+(?:[.]yaml)?\Z/, readdir REG;
        close REG;

        next USR if !@installed;

        Cpanel::initcp($usr);

        # Legacy compat
        $Cpanel::homedir = $user_homedir;

        next USR if $Cpanel::user ne $usr;

        for my $reg ( sort @installed ) {
            next unless $reg =~ /\A((?:[A-Za-z0-9_]+::){2}[A-Za-z0-9_]+)\.\d+(?:[.]yaml)?\Z/;
            my $base   = $1;
            my $module = $base;
            $module =~ s{::}{/}g;
            next unless -e "/usr/local/cpanel/cpaddons/$module.pm";

            my $regst = {};

            if ( Cpanel::cPAddons::Cache::read_cache( "$Cpanel::homedir/.cpaddons/$reg", $regst, $Cpanel::user ) ) {
                my $vers = CGI::escapeHTML( $regst->{'version'} || 'registry did not contain version' );
                my $url  = CGI::escapeHTML( $regst->{'url_to_install'} ? " at $regst->{'url_to_install'}" : '' );

                my ( undef, undef, $name ) = split /\:\:/, $reg;
                $name =~ s{\.\d+$}{};
                $name =~ s{_}{ }g;
                $name =~ s{\.yaml$}{}g;

                $cpaddoninfo{$usr}->{$base}->{$reg} = $vers;
                my $is_wordpress = $name =~ m/WordPress/;

                if ( $installedx{$base}->{'version'} ne $vers && !$is_wordpress ) {
                    require Cpanel::Redirect;
                    my $url_host = Cpanel::Redirect::getserviceSSLdomain( 'cpanel', $Cpanel::CPDATA{'DNS'} ) || $Cpanel::CPDATA{'DNS'};
                    my $base_url = "https://$url_host:2083/frontend/$Cpanel::CPDATA{'RS'}/addoncgi/cpaddons.html?addon=${\_uri($base)}";
                    $name         .= " v$vers" if $vers;
                    $needsupdated .= qq( - $name
\tLocation: $url
\tLatest: v$installedx{$base}->{'version'}
\tUpgrade here: $base_url&action=upgrade&workinginstall=${\_uri($reg)}

);
                }
            }
            else {
                $needsupdated .= "cPAddons Site Software ${\_html($reg)} could not be checked: ${\_html($!)}\n";
                $cpaddoninfo{$usr}->{$base}->{$reg} = 'Could not determine version';
            }
            if ($html) {
                my $upgrade   = '';
                my $uninstall = '';
                my $latest    = $installedx{$base}->{'version'};
                my $capabilities;
                eval "use $base;";
                if ( !$@ ) {
                    no strict 'refs';
                    my $hr = ${"$base\:\:meta_info"} || {};
                    $latest = $hr->{'version'}
                      || 'Could not determine latest version';
                    $capabilities = $hr->{capabilities};
                }
                else {
                    $latest .= " Module Error <!-- $@ -->";
                }
                my $dontprint = 0;
                my $img       = $cPAddonsConf::inst{$base}->{'version'}
                  && $base ? 'green' : 'red';
                if ( $img eq 'green' && $latest =~ m/Module Error/ ) {
                    $img = 'yellow';
                }
                my $col =
                  ( $latest eq $cpaddoninfo{$usr}->{$base}->{$reg} ) || _has_self_upgrade_capability($capabilities)
                  ? '00aa00'
                  : 'FF0000';
                if ( $show eq 'in' ) {
                    $dontprint = 1 if $installedx{$base}->{'version'};
                }
                if ( $show eq 'up' ) {
                    $dontprint = 1 if ( !_has_standard_upgrade_capability($capabilities)
                        || ( $latest eq $cpaddoninfo{$usr}->{$base}->{$reg} ) );
                }
                if ( !$dontprint ) {
                    unless ( $latest =~ m/Module Error/
                        || $cpaddoninfo{$usr}->{$base}->{$reg} =~ m/^registry did/ ) {
                        my ( $v, $c, $n ) = split /\:\:/, $base;
                        $uninstall = qq( (<a href="$ENV{'SCRIPT_NAME'}?action=un&user=$usr&inst=${\_uri($reg)}&show=${\_uri($show)}">uninstall</a>))
                          unless $img eq 'yellow';
                        $upgrade = qq( (<a href="$ENV{'SCRIPT_NAME'}?action=up&user=$usr&inst=${\_uri($reg)}&show=${\_uri($show)}">upgrade</a>))
                          if $latest ne $cpaddoninfo{$usr}->{$base}->{$reg}
                          && _has_standard_upgrade_capability($capabilities)
                          && $img ne 'yellow'
                          && -d "/usr/local/cpanel/cpaddons/$v/$c/$n/";
                    }
                    if ( defined( CGI::param('action') ) && ( CGI::param('action') eq 'upgradeall' ) ) {
                        upgrade( $usr, $reg, '<hr />' ) if $upgrade;
                    }
                    elsif ( defined( CGI::param('action') ) && ( CGI::param('action') eq 'uninstallnonwhm' ) ) {
                        uninstall( $usr, $reg, '<hr />' )
                          if $uninstall && $img eq 'red';
                    }
                    else {
                        # Don't show the version string if this addon self-updates
                        # TODO: Use the version method from the addon module, if available (See LC-6540)
                        my $current_version_string = _has_self_upgrade_capability($capabilities) ? '' : $cpaddoninfo{$usr}->{$base}->{$reg};

                        $tdshade = $tdshade eq 'tdshade2' ? 'tdshade1' : 'tdshade2';
                        my $xinstalldir = CGI::escapeHTML( $regst->{installdir} );
                        $has_installs++;
                        my $display_app_name = Cpanel::cPAddons::LegacyNaming::get_app_name($base);
                        print qq(
                            <tr class="$tdshade">
                                <td>
                                    <a href="$ENV{'SCRIPT_NAME'}?show=${\_uri($show)}&user=${\_uri($usr)}">${\_html($usr)}</a>
                                </td>
                                <td>
                                    <a target="_blank" href="$ENV{'SCRIPT_NAME'}?dumpreg=${\_uri($reg)}&user=${\_uri($usr)}">$display_app_name</a>
                                </td>
                                <td>$latest</td>
                                <td>
                                    <font color=#$col>$current_version_string</font>$upgrade
                                </td>
                                <td>
                                    <img src="/$img\-status.gif" />$uninstall $xinstalldir
                                </td>
                            </tr>
                        );
                    }
                }
            }
            else {
                $has_installs++;
                my $inst = exists $installedx{$base} ? '' : '[not in WHM list]';
                print "${\_html($usr)} ${\_html($reg)} Current: $installedx{$base}->{'version'} Installed: ${\_html($cpaddoninfo{$usr}->{$base}->{$reg})} $inst\n"
                  if !$notify;
            }
        }
        if ( $needsupdated && !$html && $notify ) {
            if ( $cpconf_ref->{'cpaddons_notify_users'} ne 'never' && ( $cpconf_ref->{'cpaddons_notify_users'} eq 'always' || -e "$Cpanel::homedir/.cpaddons_notify" ) ) {
                my $cpuser_ref   = \%Cpanel::CPDATA;
                my $user_contact = join( ',', $cpuser_ref->contact_emails_ar()->@* );
                if ($user_contact) {
                    open my $SENDMAIL, '|-', '/usr/sbin/sendmail -t' or die "Failed to start sendmail: $!";

                    # Subject is 'Site Software' instead of 'cPAddons Site Software' since it is in cpanel context not WHM
                    print {$SENDMAIL} <<"EO_USER_MESSAGE";
To: $user_contact
From: $admincontactemail
Subject: Site Software Update Notice for $usr on $hostname

Server: $hostname
Account: $usr

In order to protect the security of your website, we recommend that you upgrade
the following scripts that were installed via the "Scripts Library" in your cPanel interface:

$needsupdated

EO_USER_MESSAGE
                }
            }

            my $notify_owner = $cpconf_ref->{'cpaddons_notify_owner'} ? 1                                                 : 0;
            my $notify_root  = $cpconf_ref->{'cpaddons_notify_root'}  ? 1                                                 : 0;
            my $owner_email  = $notify_owner                          ? ( Cpanel::ContactInfo::getownercontact($usr) )[0] : '';

            require Cpanel::AcctUtils::Owner;
            my $owner = Cpanel::AcctUtils::Owner::getowner($usr);
            if ($notify_owner) {
                if ($owner_email) {
                    if (
                        $owner eq 'root'
                        || (
                            exists $reseller_acls{$owner}
                            && (   ( ref $reseller_acls{$owner} eq 'ARRAY' && grep / \A all \z /xms, @{ $reseller_acls{$owner} } )
                                || ( ref $reseller_acls{$owner} eq 'HASH' && $reseller_acls{$owner}{'all'} ) )
                        )
                    ) {
                        $owner_emails{$owner} = {} if ref $owner_emails{$owner} ne 'HASH';
                        $owner_emails{$owner}->{'email_addr'} = $owner_email;
                        $owner_emails{$owner}->{'email_body'} .= "[$usr]\n$needsupdated\n";
                    }
                }
            }

            if ($notify_root) {
                if ( $owner ne 'root' || ( $owner eq 'root' && !$notify_owner ) ) {
                    $owner_emails{'root'} = {} if ref $owner_emails{$owner} ne 'HASH';
                    $owner_emails{'root'}->{'email_addr'} = $admincontactemail;
                    $owner_emails{'root'}->{'email_body'} .= "[$usr]\n$needsupdated\n";
                }
            }
        }
    }
    else {
        warn "Could not open registry dir for $_: $!";
    }
}

sub _has_standard_upgrade_capability {
    my $capabilities = shift;
    return ( !$capabilities || $capabilities->{upgrade} && $capabilities->{upgrade}{standard} );
}

sub _has_self_upgrade_capability {
    my $capabilities = shift;
    return ( $capabilities && $capabilities->{upgrade} && $capabilities->{upgrade}{self} );
}

if ( keys %owner_emails ) {
    foreach my $user ( keys %owner_emails ) {
        next if !$owner_emails{$user}->{'email_addr'};
        open SENDMAIL, '|/usr/sbin/sendmail -t';
        print SENDMAIL <<"EO_OWNER_MESSAGE";
To: $owner_emails{$user}->{'email_addr'}
From: $admincontactemail
Subject: Software Security Notice - Script installs need upgrading

Hello $user,

In order to protect the security of your users' websites, we recommend that you
upgrade the following scripts installed via the "Scripts Library" in the cPanel interface:

$owner_emails{$user}->{'email_body'}

EO_OWNER_MESSAGE
        close SENDMAIL;
    }
}

if ( $html && !$has_installs ) {
    my $txt = '<b>There are currently no installations that match your criteria</b>';
    if ($multi) {
        print "<p>$txt</p>\n";
    }
    else {
        print qq{<tr><td colspan="5">$txt</td></tr>\n};
    }
}

print $html ? '</table>' : '' if !$multi;
print $html ? $back      : '' if $multi;
print_footer() if $html;
exit;
#### funkshuns ##

# do "main action

sub do_action {
    my $action = CGI::param('action');
    return 0 unless $action;

    my $user = scalar CGI::param('user');
    my $show = scalar CGI::param('show');
    my $inst = scalar CGI::param('inst');

    my $dispuser = defined $user ? "user=${\_uri($user)}&" : '';
    my $back     = qq(<p>[<a href="$ENV{'SCRIPT_NAME'}?${dispuser}show=${\_uri($show)}">Back</a>]</p>\n);

    if ( $action eq 'up' ) {
        upgrade( $user, $inst, $back );
        print_footer();
        exit;
    }
    elsif ( $action eq 'un' ) {
        uninstall( $user, $inst, $back );
        print_footer();
        exit;
    }
    elsif ( $action eq 'save_moderation' ) {
        _moderation_save_conf();
        print_footer();
        exit;
    }
    elsif ( $action eq 'moderation_request' ) {
        _moderation_request_list();
        print_footer();
        exit;
    }
    elsif ( $action eq 'view_moderation_req' ) {
        _moderation_view_request($admincontactemail);
        print_footer();
        exit;
    }
    elsif ( $action eq 'install_req' ) {
        _moderation_install();
        print_footer();
        exit;
    }
    elsif ( $action eq 'deny_req' ) {
        _moderation_deny();
        print_footer();
        exit;
    }
    elsif ( $action eq 'upgradeall' ) {
        print "<b>Upgrading all installs ";
        print $user ? "for ${\_html($user)}</b><br />" : "serverwide</b><br />";
        return 1;
    }
    elsif ( $action eq 'uninstallnonwhm' ) {
        print "<b>Uninstalling all installs of addons not installed via WHM ";
        print $user ? "for ${\_html($user)}</b><br />" : "serverwide</b><br />";
        if ( !CGI::param('verified') ) {
            print qq(<p><b>Are you sure you want to uninstall this?</b></p>\n<a href="$ENV{'SCRIPT_NAME'}?action=uninstallnonwhm&user=${\_uri($user)}&show=${\_uri($show)}&verified=1">Yes I am sure I want to do this.</a>\n$back);
            print_footer();
            exit;
        }
        return 1;
    }
    return 0;
}

sub upgrade {
    my ( $user, $inst, $back ) = @_;
    domainpgasuser( 'Upgrading', 'upgrade', $user, $inst, $back );
    return;
}

sub uninstall {
    my ( $user, $inst, $back, $show ) = @_;

    if ( CGI::param('verified') ) {
        domainpgasuser( 'Uninstalling', 'uninstall', $user, $inst, $back );
    }
    else {
        print qq(<p><b>Are you sure you want to uninstall this?</b></p>\n<a href="$ENV{'SCRIPT_NAME'}?action=un&user=${\_uri($user)}&inst=${\_uri($inst)}&show=${\_uri($show)}&verified=1">Yes I am sure I want to do this.</a>\n$back);
    }
    return;
}

sub domainpgasuser {
    my ( $label, $akshn, $u, $r, $back ) = @_;
    my ($addon) = $r =~ m/\A((?:[A-Za-z0-9_]+::){2}[A-Za-z0-9_]+)\.\d+(?:[.]yaml)?\Z/;

    my %input = (

        # setuid in cPAddons.pm does not work well when multiple users call this (See case 36772)
        # 'asuser'         => $u,
        'action'         => $akshn,
        'workinginstall' => $r,
        'addon'          => $addon,
        'verified'       => scalar CGI::param('verified') || 0,
    );

    print "$label ${\_html($u)} ${\_html($r)} installation here...<br />\n";

    Cpanel::AccessIds::do_as_user(
        $u,
        sub {
            my $input_hr = \%input;
            local $ENV{'CPASUSER'}         = $u;
            local $ENV{'CPNONAVFORPARENT'} = 1;
            Cpanel::initcp($u);

            # Legacy compat
            $Cpanel::homedir = $HOMES{$u} || die "Could not determine homedir for user:[$u]";

            Cpanel::cPAddons::cPAddons_init();
            Cpanel::cPAddons::cPAddons_mainpg( \%input, { called_from_root => 1 } );
        }
    );

    return print "<br />\n$back\n";
}

#### moderation ##

sub _get_installed_list {
    eval "use cPAddonsConf;";
    if ($@) {
        print "<!-- cPAddonsConf Error: $@ -->\n";
        %cPAddonsConf::inst = ();
    }
    return grep { $cPAddonsConf::inst{$_}->{'VERSION'} }
      sort keys %cPAddonsConf::inst;
}

sub _get_available_hashref {
    eval q{require "/usr/local/cpanel/cpaddons/cPAddonsAvailable.pm";};
    if ($@) {
        print "<p>Sorry - The list of available cPAddons Site Software packages could not be found or fetched!</p> <!-- $@ -->\n";
        %cPAddonsAvailable::list = ();
    }
    return \%cPAddonsAvailable::list;
}

sub _moderation_hash_form {    # return form of all installed addons Foo::Bar => 0|1
    my $moderated = {};
    if ( -e '/var/cpanel/cpaddons_moderated.yaml' ) {
        if ( !Cpanel::cPAddons::Cache::read_cache( '/var/cpanel/cpaddons_moderated', $moderated ) ) {
            return qq(<p id="er">/var/cpanel/cpaddons_moderated.yaml unreadable: $!</p>\n);
        }
    }

    my $has_moderated_addon = 0;
    my $form                = '';
    my $moderation_section  = '';
    my $available_ref       = _get_available_hashref();
    for my $ado ( sort keys %{$available_ref} ) {

        my $display_app_name = Cpanel::cPAddons::LegacyNaming::get_app_name($ado);

        # Do no allow any action on blacklisted addon
        next if ( Cpanel::cPAddons::Filter::is_blacklisted($ado) );

        # Do not display moderation capabilities if:
        #  1. The cpaddon is not installed; and
        #  2. The cpaddon appears on the deprecated list
        next if ( $cPAddonsConf::inst{$ado}->{'VERSION'} == 0 && Cpanel::cPAddons::Filter::is_deprecated($ado) );

        # If the addon is not already marked for moderation, don't display the option to enable moderation on it.
        # This is the first step toward removing the moderation feature entirely.
        next if !$moderated->{$ado};

        my $checked =
             exists $available_ref->{$ado}
          && exists $moderated->{$ado}
          && $moderated->{$ado} ? ' checked="checked"' : '';
        $form .= qq(
        <div class="checkbox">
            <label><input type="checkbox" name="$ado" value="1"$checked /> $display_app_name</label>
        </div>
        );
        $has_moderated_addon = 1;
    }

    if ($has_moderated_addon) {
        $moderation_section .= qq{
    <form action="$ENV{'SCRIPT_NAME'}" method="post">
        <input type="hidden" name="action" value="save_moderation" />
        $form
        <p>
            <button type="submit" class="btn btn-primary">
                Update Moderation
            </button>
        </p>
    </form>
        };
    }

    my $instructions = "You cannot enable moderation for any cPAddons.";
    if ($has_moderated_addon) {
        $instructions = "You can disable moderation for a cPAddon that already uses moderation. However, you cannot enable moderation for any cPAddons.";
    }

    $moderation_section = <<"FORM_END";
<div style="margin-left:20px; width: 80%">
    <h3>Moderation Configuration</h3>

    <div class="alert alert-info alert-dismissable">
        <span class="glyphicon glyphicon-info-sign"></span>
        <div class="alert-message">
            <strong>Info:</strong>
            We have deprecated the moderation feature and will remove it in the future.
            $instructions
        </div>
    </div>
    $moderation_section
</div>
FORM_END

    return $moderation_section;
}

sub _moderation_save_conf {    # write /var/cpanel/cpaddons_moderated
    my $mod_conf      = {};
    my $available_ref = _get_available_hashref();
    for my $ado ( sort keys %{$available_ref} ) {
        $mod_conf->{$ado} = 1 if CGI::param($ado);
    }
    Cpanel::cPAddons::Cache::write_cache( '/var/cpanel/cpaddons_moderated', $mod_conf );
    chmod 0644, '/var/cpanel/cpaddons_moderated.yaml';
    print qq{<br /><div><h4>Moderation configuration saved.</h4></div><br />\n};
    print qq{<p>[<a href="$ENV{'SCRIPT_NAME'}">Back</a>]</p>\n};
}

sub _moderation_serverwide_requests {
    my %req;

  USERLOOP:
    for my $user (@USERS) {
        my $user_homedir = Cpanel::PwCache::gethomedir($user);

        my $dir = "$user_homedir/.cpaddons/moderation/";
        if ( !-d $dir ) {
            Cpanel::AccessIds::ReducedPrivileges::call_as_user( sub { Cpanel::SafeDir::MK::safemkdir($dir) }, $user );
        }

        if ( opendir my $req_dh, $dir ) {
          REQUESTLOOP:
            for my $req ( readdir $req_dh ) {
                next REQUESTLOOP if $req =~ m{ \A [.] [.]? \z }xms || $req =~ tr/<>&'"//;
                $req{$user}->{"$dir$req"} = 1;
            }
            closedir $req_dh;
        }
        else {

            # for now silence is golden
            # could not readdir $dir: $!
        }
    }
    return wantarray ? %req : \%req;
}

sub _moderation_view_reqs_link {    # action=moderation_request
    my $got_requests = _moderation_serverwide_requests();
    my $link         = '';
    if ( scalar keys %{$got_requests} ) {
        $link .= qq{
        <style>
            .pending-moderation-reqs {
                margin-left: 20px;
                margin-bottom: 20px;
                border: 1px solid #e5e5e5;
                padding: 0 15px 20px 15px;
                width: 80%
            }

            .pending-moderation-reqs .links-list td {
                padding-left: 10px;
                padding-right: 10px;
            }

            .pending-moderation-reqs .links-list td
        </style>
        <div class="pending-moderation-reqs">
            <h3>Pending Moderation Requests</h3>
            <table class="links-list">
            };

        foreach my $user ( sort keys %{$got_requests} ) {
            my $tcount = 0;
            my $tclass = 'tdshade1';
            $link .= qq{
                <tr>
                    <th align="left">User: <span id="user">${\_html($user)}</span></th>
                </tr>
            };
            foreach my $req ( sort keys %{ $got_requests->{$user} } ) {
                $tclass = ( ( $tcount % 2 ) == 0 ) ? 'tdshade1' : 'tdshade2';

                my ($yaml_file) = $req =~ m{ ([^/]+) \z }xms;
                my ( $mod, $num ) = $yaml_file =~ m{^ ([^.]+) \. (\d+) \. yaml $}x;
                my $request_name =
                  $mod
                  ? sprintf( '%s - Request %s', Cpanel::cPAddons::LegacyNaming::get_app_name($mod), $num )
                  : $yaml_file;

                my $url = "$ENV{'SCRIPT_NAME'}?action=view_moderation_req&amp;req=${\_uri($req)}&amp;source=popup";
                my $id  = $user . "_" . $req;
                $link .= qq{
                <tr class="$tclass">
                    <td>
                        <a href="" target="_blank" id="${\_html($id)}"
                           onclick="window.open('$url','name','height=450,width=600,toolbar=no,status=no,menubar=no,scrollbars=1'); return false;">
                           ${\_html($request_name)}
                        </a>
                    </td>
                </tr>
                };
                $tcount++;
            }
        }
        $link .= qq{
            </table>
        </div>
        };

        #return qq(<p><a href="$ENV{'SCRIPT_NAME'}?action=moderation_request">View Pending moderation request</a></p>\n);
    }
    return $link;
}

sub _moderation_request_list {    # action=view_moderation_req&req=$file
    my $needsform = shift || 0;
    my %requests  = _moderation_serverwide_requests();
    print qq{
    <table width="80%">
    };
    for my $usr ( sort keys %requests ) {
        print qq(
            <tr>
                <td><b>${\_html($usr)}</b></td>
            </tr>
        );

        for my $req ( sort keys %{ $requests{$usr} } ) {
            my $name = $req;
            ($name) = $name =~ m{ ([^/]+) \z }xms;
            my $url = "$ENV{'SCRIPT_NAME'}?action=view_moderation_req&req=${\_uri($req)}";
            if ($needsform) {
                print qq(
                <tr>
                    <td>
                        <input name="${\_html($req)}" type="check">
                    </td>
                    <td>
                        <a href="$url">${\_html($name)}</a>
                    </td>
                </tr>
                );
            }
            else {
                print qq(
                <tr>
                    <td>
                        <a href="$url">${\_html($name)}</a>
                    </td>
                </tr>
                );
            }
        }
        print qq(
            </table>
        );
    }
}

# This looks down for the first directory that is not root-owned and returns the
# user it belongs to.
sub _find_user_by_home_directory {
    my $path = shift;

    return unless -e $path;

    my @components = grep { $_ ne ".." } split /\//, $path;
    my $composed   = "";
    while ( defined( my $piece = shift @components ) ) {
        $composed .= "/$piece";
        return unless -d $composed;
        my $uid = ( stat(_) )[4];
        return scalar Cpanel::PwCache::getpwuid($uid) if $uid;
    }
    return;
}

sub _moderation_view_request {    # action=install_req&req=$req action=deny_req&req=$req
    my $admincontactemail = shift;
    my $req;
    {
        # CGI::param called in list context can lead to vulnerabilities.
        #   http://blog.gerv.net/2014.10/new-class-of-vulnerability-in-perl-web-applications
        # from the previous url sample, seems like we can have multiple 'req' entries
        local $CGI::LIST_CONTEXT_WARN;    # avoid a once warning
        $CGI::LIST_CONTEXT_WARN = 0;
        $req                    = CGI::param('req');
    }

    my $ispopup = CGI::param('source') eq 'popup' ? 1 : 0;

    my $user = _find_user_by_home_directory($req);

    if ($user) {
        my $name = $req;
        ($name) = $name =~ m{ ([^/]+) \z }xms;

        my $req_hr = {};
        Cpanel::cPAddons::Cache::read_cache( $req, $req_hr, $user );
        return if !keys %{$req_hr};

        if ( $req_hr->{'input_hr'}{'asuser'} ) {
            my ($resellercontactemail) = Cpanel::ContactInfo::getownercontact( $req_hr->{'input_hr'}{'asuser'}, 'root' => 'skip' );
            $admincontactemail = $resellercontactemail ? $resellercontactemail : $admincontactemail;
        }

        my $msg = CGI::escapeHTML( $req_hr->{'msg'} );
        $msg = '>> ' . $msg;
        $msg =~ s{ \n }{\n>> }xmsg;
        my $date = localtime( $req_hr->{'date'} );

        my $asuser = $req_hr->{'iddnput_hr'}->{'asuser'};
        my $email  = $req_hr->{'input_hr'}->{'email'};

        print <<"REQ_END";
<style>
    #masterContainer {
        margin-top: 0;
    }
    td {
        padding: 0 5px 5px 5px
    }
</style>
<table style="margin-top:20px">
    <tr>
        <td>
            <form action="$ENV{'SCRIPT_NAME'}" name="moderation_action" id="form">
                <input type="hidden" name="req" value="${\_html($req)}">
                <input type="hidden" name="reqname" value="${\_html($name)}">
                <input type="hidden" name="action" id="action">

                <table>
                    <tr>
                        <td>
                            <b>From:</b>
                        </td>
                        <td>
                            <input type="text" name="reply-to" value="$admincontactemail" class="form-control"  />
                        </td>
                    </tr>
                    <tr>
                        <td><b>To (${\_html($asuser)}):</b></td>
                        <td>
                            <input type="text" name="email" value="${\_html($email)}" class="form-control"  />
                        </td>
                    </tr>
                    <tr>
                        <td><b>Request:</b><td>${\_html($name)}</td>
                    </tr>
                    <tr>
                        <td><b>Date:</b></b><td>$date</td>
                    </tr>
                    <tr>
                        <td colspan="2"><b>Reply:</b></td>
                    </tr>
                    <tr>
                        <td colspan="2">
                            <textarea name="msg" cols="70" rows="5" class="form-control" >$msg</textarea>
                        </td>
                    </tr>
                    <tr>
                        <td>
                            <button type="submit" class="btn btn-primary" id="install-req">
                                Install
                            </button>
                            <span id="install-req-spinner" style="display:none">
                                <i class="fas fa-spinner fa-spin" aria-hidden="true" ></i>
                                Installing ...
                            </span>
                        </td>
                        <td>
                            <span id="deny-req-spinner" style="display:none">
                                <i class="fas fa-spinner fa-spin" aria-hidden="true" ></i>
                                Notifying ...
                            </span>
                            <button type="submit" class="btn btn-btn-default pull-right" id="deny-req">
                            Deny Request
                            </button>
                        </td>
                    </tr>
                </table>
                <script>
                    window.addEventListener("load", function() {
                        \$("#install-req").click(function() {
                            \$("#action").val("install_req");
                            \$("#form").submit();
                            \$("#install-req").prop( "disabled", true );
                            \$('#install-req-spinner').show();
                            \$("#deny-req").prop( "disabled", true );
                        });
                        \$("#deny-req").click(function() {
                            \$("#action").val("deny_req");
                            \$("#form").submit();
                            \$("#install-req").prop( "disabled", true );
                            \$('#deny-req-spinner').show();
                            \$("#deny-req").prop( "disabled", true );
                        });
                    });
                </script>
            </form>
        </td>
    </tr>
</table>
REQ_END
    }
    else {
        print "Could not find that request!";
    }

    print qq(
        <p>
            [<a href="$ENV{'SCRIPT_NAME'}?action=moderation_request">Back</a>]
        </p>
    ) if !$ispopup;
}

sub _moderation_install {
    my $req  = CGI::param('req');
    my $user = _find_user_by_home_directory($req);

    if ($user) {

        my $req_hr = {};
        Cpanel::cPAddons::Cache::read_cache( $req, $req_hr, $user );
        return if !keys %{$req_hr};

        Cpanel::AccessIds::do_as_user(
            $user,
            sub {
                my $input_hr = $req_hr->{input_hr};

                local $ENV{'CPASUSER'}         = $user;
                local $ENV{'CPNONAVFORPARENT'} = 1;
                Cpanel::initcp($user);
                $Cpanel::homedir = $HOMES{$user} || die "Could not determine homedir for user:[$user]";

                Cpanel::cPAddons::cPAddons_init();
                Cpanel::cPAddons::cPAddons_mainpg( $input_hr, { called_from_root => 1 } );
                unlink $req or print qq(Could not remove request: $!</p>\n);
            },
        );

        _send_installed_message(
            scalar CGI::param('msg'),
            scalar CGI::param('reqname'),
            scalar CGI::param('email'),
            scalar CGI::param('reply-to')
        );
    }
    else {
        my $url = "$ENV{'SCRIPT_NAME'}?action=moderation_request";
        print qq(
            <p>
                <b>Could not find that request!</b>
            </p>
            <p>
                [<a href="$url" id="back">Back</a>]
            </p>
        );
    }

    return;
}

sub _moderation_deny {
    my $quiet = shift || 0;
    my $req   = CGI::param('req');
    if ( !$quiet && CGI::param('msg') && CGI::param('email') ) {
        _send_request_denied_message( scalar CGI::param('msg'), scalar CGI::param('reqname'), scalar CGI::param('email'), scalar CGI::param('reply-to') );
    }
    if ( -e $req ) {
        my $user = _find_user_by_home_directory($req);
        if ($user) {
            print qq(<h2>Removing request</h2>\n) if !$quiet;
            Cpanel::AccessIds::ReducedPrivileges::call_as_user(
                sub {
                    unlink $req or print qq(Could not remove request: $!\n);
                },
                $user
            );
        }
    }
    else {
        print qq(<p><b>Could not find that request!</b></p>\n);
    }
    print qq(<p>[<a href="" onclick="window.close()">Close</a>]</p>\n)
      if !$quiet;

    return;
}

sub _send_installed_message {
    my $msg     = shift;
    my $reqname = shift;
    my $email   = shift;
    my $from    = shift;
    $reqname = 'RE: cPAddons Site Software request ' . $reqname . ' - Installed';
    return _send_message( $email, $from, $reqname, $msg );
}

sub _send_request_denied_message {
    my $msg     = shift;
    my $reqname = shift;
    my $email   = shift;
    my $from    = shift;
    $reqname = 'RE: cPAddons Site Software request ' . $reqname . ' - Request Denied';
    return _send_message( $email, $from, $reqname, $msg );
}

sub _send_message {
    my $receiver = shift;
    my $sender   = shift || $admincontactemail;
    my $subject  = shift;
    my $message  = shift;

    if ( !$receiver ) {
        warn "Unable to send message to blank recipient\n";
        return;
    }

    if ( !Cpanel::Validate::EmailRFC::is_valid($receiver) ) {
        warn "Recipient email address is not valid\n";
        return;
    }

    if ( !Cpanel::Validate::EmailRFC::is_valid($sender) ) {
        warn "Sender email address is not valid\n";
        return;
    }

    if ( $subject =~ /\n/ ) {
        warn "Subject can not contain newlines\n";
        return;
    }

    if ( open my $SENDMAIL, '|-', '/usr/sbin/sendmail -t' ) {
        print {$SENDMAIL} <<"EO_MESSAGE";
To: $receiver
From: $sender
Subject: $subject


$message
EO_MESSAGE
        close $SENDMAIL;
        return 1;
    }
    else {
        warn "Unable to send message: $!";
        return;
    }
}

sub print_header {
    return if !$html;
    my $ispopup = ( defined( CGI::param('source') ) && ( CGI::param('source') eq 'popup' ) ) ? 1 : 0;

    Cpanel::Template::process_template(
        'whostmgr',
        {
            'print'                        => 1,
            'template_file'                => 'master_templates/_defheader.tmpl',
            'theme'                        => 'bootstrap',
            'app_key'                      => 'manage_cpaddons_site_software',
            'include_legacy_stylesheets'   => 1,
            'inside_frame_or_tab_or_popup' => $ispopup,
            'extrastyle'                   => qq(
                .whm-app-title__image{width:48px;height:48px}
            ),

        },
    );
    return;
}

sub print_footer {
    return if !$html;
    my $ispopup = ( defined( CGI::param('source') ) && ( CGI::param('source') eq 'popup' ) ) ? 1 : 0;

    Cpanel::Template::process_template(
        'whostmgr',
        {
            'print'                        => 1,
            'template_file'                => 'master_templates/_deffooter.tmpl',
            'theme'                        => 'bootstrap',
            'include_legacy_stylesheets'   => 1,
            'inside_frame_or_tab_or_popup' => $ispopup,
            'skipsupport'                  => 1,
            'scripts'                      => [
                '../libraries/jquery/current/jquery.min.js',
            ]
        },
    );
    return;
}

sub _print_actions {
    my ($users) = @_;
    my $opts;
    for ( sort @$users ) {
        $opts .= qq(                <option name="${\_html($_)}" value="${\_html($_)}">${\_html($_)}</option>\n);
    }

    my $form = <<"FORM";
<div style="margin-left:20px;">
    <h3>Manage Users Site Software</h3>
    <form action="$ENV{'SCRIPT_NAME'}" method="post">
        <p>
            Show
            <select name="show" id="filter_type">
                <option value="up" selected>All Outdated Installations</option>
                <option value="in">Orphaned Installations</option>
                <option value="">All Installations</option>
            </select>
            for
            <select name="user" id="selected-user-to-manage">
                <option value="">All Users</option>
$opts
            </select>
            <button type="submit" class="btn btn-primary" id="btn-manage-selected">
                Manage
            </button>
        </p>
    </form>
    <form action="$ENV{'SCRIPT_NAME'}" method="post">
            <p>
            <select name="action">
                <option value="upgradeall" selected>Upgrade All Installations</option>
                <option value="uninstallnonwhm">Uninstall All Orphaned Installations</option>
            </select>
            for
            <select name="user" id="selected-user-to-uninstall">
                <option value="">All Users</option>
$opts
            </select>
            <button type="submit" class="btn btn-primary" id="btn-uninstall-selected">
                Go
            </button>
        </p>
    </form>
</div>
FORM
    return $form;
}

sub _html {
    return CGI::escapeHTML(@_);
}

sub _uri {
    return Cpanel::Encoder::URI::uri_encode_str(@_);
}
