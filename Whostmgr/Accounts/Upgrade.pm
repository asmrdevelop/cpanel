package Whostmgr::Accounts::Upgrade;

# cpanel - Whostmgr/Accounts/Upgrade.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::AcctUtils::Account         ();
use Cpanel::BandwidthMgr               ();
use Cpanel::Config::CpUserGuard        ();
use Cpanel::DomainIp                   ();
use Cpanel::Exception                  ();
use Cpanel::Hooks                      ();
use Cpanel::IP::Remote                 ();
use Cpanel::LoadModule                 ();
use Cpanel::Locale                     ();
use Cpanel::PwCache                    ();
use Cpanel::PwCache::Get               ();
use Cpanel::Quota                      ();
use Cpanel::Services::Cpsrvd           ();
use Cpanel::Shell                      ();
use Cpanel::Sys::Hostname              ();
use Whostmgr::ACLS                     ();
use Whostmgr::Accounts::Shell::Default ();
use Whostmgr::Accounts::Shell          ();
use Whostmgr::AcctInfo::Owner          ();
use Whostmgr::Func                     ();
use Whostmgr::Packages::Fetch          ();
use Whostmgr::Packages::Legacy         ();
use Whostmgr::Packages::Load           ();
use Whostmgr::Packages::Info::Modular  ();

use Try::Tiny;

my $locale;

sub upacct {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my %OPTS = @_;
    my $user = $OPTS{'user'};
    my $plan = $OPTS{'pkg'};
    my $output;
    my $pkg = $plan;

    if ( !$user || $user eq '' ) {
        return ( 0, "Sorry, you must specify a user!" );
    }
    if ( !$plan || $plan eq '' ) {
        return ( 0, "Sorry, you must select a new package!" );
    }

    if ( !Whostmgr::ACLS::hasroot() && !Whostmgr::AcctInfo::Owner::checkowner( $ENV{'REMOTE_USER'}, $user ) ) {
        return ( 0, "Umm.. what are you trying to pull here..\nYou do not own the user $user\n" );
    }

    return ( 0, "Sorry, the user $user does not exist" ) if !Cpanel::AcctUtils::Account::accountexists($user);
    Cpanel::LoadModule::load_perl_module('Whostmgr::Bandwidth');

    my $homedir = Cpanel::PwCache::gethomedir($user);

    my $cpuser_guard = Cpanel::Config::CpUserGuard->new($user);

    if ( !$cpuser_guard ) {
        return ( 0, "Internal Error, this user has no cPanel users configuration file" );
    }

    my $cpuser_data = $cpuser_guard->{'data'};

    my %result_hash;
    my $pkg_ref = Whostmgr::Packages::Load::load_package( $pkg, \%result_hash );
    if ( !$result_hash{'result'} ) {
        return ( 0, 'Specified package does not exist.' );
    }

    my $pkglist_ref = Whostmgr::Packages::Fetch::fetch_package_list(
        'want'                    => 'creatable',
        'package'                 => $pkg,
        'test_without_user'       => { 'user' => $user },
        'test_with_less_packages' => {
            'package' => $cpuser_data->{'PLAN'},
            'count'   => 1,
        }
    );

    if ( !$pkglist_ref->{$pkg} ) {
        return ( 0, "Sorry you may not create any more accounts with the package $pkg." );
    }

    my $cur_pkg = $cpuser_data->{'PLAN'};

    my $hook_info = {
        'category' => 'Whostmgr',
        'event'    => 'Accounts::change_package',
        'stage'    => 'pre',
        'blocking' => 1,
    };
    my ( $pre_hook_result, $hook_msgs ) = Cpanel::Hooks::hook(
        $hook_info,
        {
            'cur_pkg' => $cur_pkg,
            'new_pkg' => $pkg,
            'user'    => $user,
        },
    );
    return ( 0, Cpanel::Hooks::hook_halted_msg( $hook_info, $hook_msgs ) ) if !$pre_hook_result;

    $output .= "<pre>\n";

    my (
        $useip,
        $cgi,
        $quota,
        undef,    # deprecated entry - frontpage - case 104361
        $cpmod,
        $maxftp,
        $maxsql,
        $maxpop,
        $maxlst,
        $maxsub,
        $bwlimit,
        $hasshell,
        $maxpark,
        $maxaddon,
        $featurelist,
        $pkglocale,
        $maxemailsperhour,
        $email_send_limits_max_defer_fail_percentage,
        undef,    # deprecated entry - email_send_limits_min_defer_fail_to_trigger_protection - case 51825
        $digestauth,
        $max_emailacct_quota,
        $maxpassengerapps,
        $max_team_users,
    ) = Whostmgr::Packages::Legacy::pkgref_to_old_format( $pkglist_ref->{$pkg} );

    $useip ||= 0;

    $locale ||= Cpanel::Locale->get_handle();

    my $bbwlimit = Whostmgr::Func::unlimitedint( $bwlimit, sub { 1024 * 1024 * shift() } ) || 'unlimited';

    $output .= $locale->maketext( "Changing the account bandwidth limit from “[_1]” to “[_2]”.", $cpuser_data->{'BWLIMIT'}, $bbwlimit ) . "\n";
    $cpuser_data->{'BWLIMIT'} = $bbwlimit;

    $featurelist ||= 'default';
    $output .= "Changing Feature List to $featurelist\n";
    $cpuser_data->{'FEATURELIST'} = $featurelist;

    $output .= $locale->maketext( "Changing the maximum email accounts from “[_1]” to “[_2]”.", $cpuser_data->{'MAXPOP'}, ( $maxpop // 'unlimited' ) ) . "\n";
    $cpuser_data->{'MAXPOP'} = defined $maxpop ? $maxpop : 'unlimited';

    $output .= $locale->maketext( "Changing the maximum SQL databases from “[_1]” to “[_2]”.", $cpuser_data->{'MAXSQL'}, ( $maxsql // 'unlimited' ) ) . "\n";
    $cpuser_data->{'MAXSQL'} = defined $maxsql ? $maxsql : 'unlimited';

    $output .= $locale->maketext( "Changing the maximum FTP accounts from “[_1]” to “[_2]”.", $cpuser_data->{'MAXFTP'}, ( $maxftp // 'unlimited' ) ) . "\n";
    $cpuser_data->{'MAXFTP'} = defined $maxftp ? $maxftp : 'unlimited';

    $output .= $locale->maketext( "Changing the maximum mailing lists from “[_1]” to “[_2]”.", $cpuser_data->{'MAXLST'}, ( $maxlst // 'unlimited' ) ) . "\n";
    $cpuser_data->{'MAXLST'} = defined $maxlst ? $maxlst : 'unlimited';

    $output .= $locale->maketext( "Changing the maximum subdomains from “[_1]” to “[_2]”.", $cpuser_data->{'MAXSUB'}, ( $maxsub // 'unlimited' ) ) . "\n";
    $cpuser_data->{'MAXSUB'} = defined $maxsub ? $maxsub : 'unlimited';

    $output .= $locale->maketext( "Changing the locale from “[_1]” to “[_2]”.", $cpuser_data->{'LOCALE'}, ( $pkglocale // 'en' ) ) . "\n";
    $cpuser_data->{'LOCALE'} = defined $pkglocale ? $pkglocale : 'en';

    my ( $old_email_quota, $new_email_quota );

    if ( $cpuser_data->{'MAX_EMAILACCT_QUOTA'} && $cpuser_data->{'MAX_EMAILACCT_QUOTA'} ne "unlimited" ) {
        $old_email_quota = $locale->format_bytes( $cpuser_data->{'MAX_EMAILACCT_QUOTA'} * 1024 * 1024 );
    }
    else {
        $old_email_quota = $locale->maketext("unlimited");
    }

    if ( $max_emailacct_quota && $max_emailacct_quota ne "unlimited" ) {
        $new_email_quota = $locale->format_bytes( $max_emailacct_quota * 1024 * 1024 );
    }
    else {
        $new_email_quota = $locale->maketext("unlimited");
    }

    $output .= $locale->maketext( "Changing the maximum email quota from “[_1]” to “[_2]” …", $old_email_quota, $new_email_quota ) . "\n";
    $cpuser_data->{'MAX_EMAILACCT_QUOTA'} = defined $max_emailacct_quota ? $max_emailacct_quota : 'unlimited';

    if ( defined $maxemailsperhour ) {
        $output .= "Changing \"Maximum Hourly Email by Domain Relayed\" from " . ( $cpuser_data->{'MAX_EMAIL_PER_HOUR'} || "unlimited" ) . " to $maxemailsperhour\n";
        $cpuser_data->{'MAX_EMAIL_PER_HOUR'} = $maxemailsperhour;
    }
    else {
        delete $cpuser_data->{'MAX_EMAIL_PER_HOUR'};
    }

    if ( defined $email_send_limits_max_defer_fail_percentage ) {
        $output .= "Changing \"Maximum percentage of failed or deferred messages a domain may send per hour\" from " . ( $cpuser_data->{'MAX_DEFER_FAIL_PERCENTAGE'} || "unlimited" ) . " to $email_send_limits_max_defer_fail_percentage\n";
        $cpuser_data->{'MAX_DEFER_FAIL_PERCENTAGE'} = $email_send_limits_max_defer_fail_percentage;
    }
    else {
        delete $cpuser_data->{'MAX_DEFER_FAIL_PERCENTAGE'};
    }

    if ( defined $maxpassengerapps ) {
        if ( defined $cpuser_data->{'MAXPASSENGERAPPS'} ) {
            $output .= $locale->maketext( "Changing the maximum passenger applications from “[_1]” to “[_2]”.", $cpuser_data->{'MAXPASSENGERAPPS'}, $maxpassengerapps ) . "\n";
        }
        else {
            $output .= $locale->maketext( "Setting the maximum passenger applications to “[_1]”.", $maxpassengerapps ) . "\n";
        }
        $cpuser_data->{'MAXPASSENGERAPPS'} = $maxpassengerapps;
    }
    else {
        delete $cpuser_data->{'MAXPASSENGERAPPS'};
    }

    if ( defined $max_team_users ) {
        if ( defined $cpuser_data->{'MAX_TEAM_USERS'} ) {
            $output .= $locale->maketext( "Changing the maximum team users with roles from “[_1]” to “[_2]”.", $cpuser_data->{'MAX_TEAM_USERS'}, $max_team_users ) . "\n";
        }
        else {
            $output .= $locale->maketext( "Setting the maximum team users with roles to “[_1]”.", $max_team_users ) . "\n";
        }
        $cpuser_data->{'MAX_TEAM_USERS'} = $max_team_users;
    }
    else {
        delete $cpuser_data->{'MAX_TEAM_USERS'};
    }

    #We do NOT change the account's LOCALE setting, even though it's part of the package.
    $output .= $locale->maketext( "Changing the maximum parked domains from “[_1]” to “[_2]”.", $cpuser_data->{'MAXPARK'}, ( $maxpark || 0 ) ) . "\n";
    $cpuser_data->{'MAXPARK'} = defined $maxpark ? $maxpark : 0;

    $output .= $locale->maketext( "Changing the maximum addon domains from “[_1]” to “[_2]”.", $cpuser_data->{'MAXADDON'}, ( $maxaddon || 0 ) ) . "\n";
    $cpuser_data->{'MAXADDON'} = defined $maxaddon ? $maxaddon : 0;

    _set_modular_components( $cpuser_data, $pkglist_ref->{$pkg}, \$output );

    # package extensions

    # remove extensions no longer supported
    my @current_extensions = ();
    if ( $cpuser_data->{'_PACKAGE_EXTENSIONS'} ) {
        @current_extensions = split( m/\s+/, $cpuser_data->{'_PACKAGE_EXTENSIONS'} );
    }
    my $extensions_dir = Whostmgr::Packages::Load::package_extensions_dir();
    foreach my $extension (@current_extensions) {
        my $extension_defaults = Whostmgr::Packages::Load::load_package_file_raw("$extensions_dir$extension");
        foreach my $extension_var ( keys %{$extension_defaults} ) {
            next if ( $extension_var eq '_NAME' );    # This is for display only
            delete $cpuser_data->{$extension_var};
        }
    }

    my @supported_extensions = ();
    if ( $pkg_ref->{'_PACKAGE_EXTENSIONS'} ) {
        @supported_extensions = split( m/\s+/, $pkg_ref->{'_PACKAGE_EXTENSIONS'} );
        $cpuser_data->{'_PACKAGE_EXTENSIONS'} = $pkg_ref->{'_PACKAGE_EXTENSIONS'};
    }
    else {
        $cpuser_data->{'_PACKAGE_EXTENSIONS'} = '' if $cpuser_data->{'_PACKAGE_EXTENSIONS'};
    }

    foreach my $extension (@supported_extensions) {
        my $extension_defaults = Whostmgr::Packages::Load::load_package_file_raw("$extensions_dir$extension");
        foreach my $extension_var ( keys %{$extension_defaults} ) {
            next                                                        if ( $extension_var eq '_NAME' );           # This is for display only
            $cpuser_data->{$extension_var} = $pkg_ref->{$extension_var} if defined( $pkg_ref->{$extension_var} );
        }
    }

    my $current_shell = Cpanel::PwCache::Get::getshell($user) || q{};

    # The default package has this set to undef.
    $hasshell //= 'n';
    if ( !Whostmgr::ACLS::checkacl('allow-shell') || $hasshell eq 'n' ) {
        if ( $current_shell eq $Cpanel::Shell::NO_SHELL ) {
            $output .= "Shell Access Set Correctly (noshell)\n";
        }
        else {
            $output .= "Removing Shell Access\n";
            $output .= Whostmgr::Accounts::Shell::set_shell( $user, $Cpanel::Shell::NO_SHELL );
        }
    }
    else {
        my $shell = Whostmgr::Accounts::Shell::Default::get_default_shell();
        if ( $current_shell eq $shell ) {
            $output .= "Shell Access Set Correctly\n";
        }
        else {
            $output .= "Adding Shell Access\n";
            $output .= Whostmgr::Accounts::Shell::set_shell( $user, $shell );
        }
    }

    my $oldpkg;
    {
        local $cpuser_data->{RS} = $cpuser_data->{RS} || "";
        $output .= "Changing cPanel theme from $cpuser_data->{'RS'} to $cpmod\n";
    }
    $cpuser_data->{'RS'} = $cpmod;
    $oldpkg = $cpuser_data->{'PLAN'};
    $output .= "Changing plan from $cpuser_data->{'PLAN'} to $pkg\n";
    $cpuser_data->{'PLAN'} = $pkg;

    # Update CGI setting for all domains and user
    $cgi ||= 'y';
    my $hascgi         = $cgi eq 'n' ? 0 : 1;
    my $changed_hascgi = $hascgi ne $cpuser_data->{'HASCGI'};
    $cpuser_data->{'HASCGI'} = $hascgi;

    my $bytes_used_this_month = Whostmgr::Bandwidth::get_acct_bw_usage_this_month( $user, $cpuser_data );
    my $pbytes                = $bytes_used_this_month;
    if ( int($pbytes) == 0 ) { $pbytes = 'unlimited'; }

    if ( $bbwlimit eq "0" || $bbwlimit =~ /unlimited/i || $bbwlimit > $bytes_used_this_month ) {
        $output .= "Bandwidth limit ($bbwlimit) is lower than ($pbytes) (all limits removed)<br />";
        $output .= "<blockquote><div style='float:left;'>Enabling...</div>";
        Cpanel::BandwidthMgr::disablebwlimit( $user, $cpuser_data->{'DOMAIN'}, $bbwlimit, $pbytes, 1, $cpuser_data->{'DOMAINS'} );

        foreach my $dns ( @{ $cpuser_data->{'DOMAINS'} }, $cpuser_data->{'DOMAIN'} ) {
            $output .= "<div style='float:left;'>...$dns...</div>";
        }
        $output .= "<div style='float:left;'>Done</div>";
        $output .= "</blockquote><br /><div class='clearit' style='clear:both; width:80%;'>&nbsp;</div>";
    }
    else {
        $output .= "Bandwidth limit ($bbwlimit) is higher than ($bytes_used_this_month)<br />";
        if ( -e '/var/cpanel/bwlimitcheck.disabled' ) {
            $output .= "(skipping bandwidth check)<br />";
        }
        else {
            $output .= "(site has been limited)<br /><blockquote><div style='float:left;'>Disabling...</div>";
            Cpanel::BandwidthMgr::enablebwlimit( $user, $cpuser_data->{'DOMAIN'}, $bbwlimit, $pbytes, 1, $cpuser_data->{'DOMAINS'} );
            foreach my $dns ( @{ $cpuser_data->{'DOMAINS'} }, $cpuser_data->{'DOMAIN'} ) {
                $output .= "<div style='float:left;'>...$dns...</div>";
            }
            $output .= "<div style='float:left;'>Done</div>";
            $output .= "</blockquote><br /><div class='clearit' style='clear:both; width:80%;'>&nbsp;</div>";
        }
    }

    my $ip = Cpanel::DomainIp::getdomainip( $cpuser_data->{'DOMAIN'} );
    $cpuser_data->{'IP'} = $ip;

    my $host = Cpanel::Sys::Hostname::gethostname();

    $cpuser_guard->save();    # must close the cpanel users file before changing the quota

    $output .= $locale->maketext( "Setting quota to “[_1]”.", ( $quota || 'unlimited' ) ) . "\n";
    $quota ||= 0;

    Cpanel::LoadModule::load_perl_module('Cpanel::Quota::Blocks');
    Cpanel::LoadModule::load_perl_module('Cpanel::Quota::Common');
    my $blocks = $quota =~ m{unlimited}i ? 0 : ( $quota * $Cpanel::Quota::Common::MEGABYTES_TO_BLOCKS );
    try {
        'Cpanel::Quota::Blocks'->new()->set_user($user)->set_limits_if_quotas_enabled( { soft => $blocks, hard => $blocks } );
    }
    catch {
        $output .= Cpanel::Exception::get_string($_);
    };

    Cpanel::Quota::reset_cache($user);

    my %notify_opts = (
        'user'              => $user,
        'user_domain'       => $cpuser_data->{'DOMAIN'},
        'ip'                => $ip,
        'new_plan'          => $cpuser_data->{'PLAN'},
        'old_plan'          => $oldpkg,
        'host'              => $host,
        'env_remote_user'   => $ENV{'REMOTE_USER'},
        'env_user'          => $ENV{'USER'},
        'origin'            => 'WHM',
        'source_ip_address' => Cpanel::IP::Remote::get_current_remote_ip(),
    );

    require Cpanel::Notify::Deferred;
    Cpanel::Notify::Deferred::notify(
        'class'            => 'upacct::Notify',
        'application'      => 'upacct::Notify',
        'constructor_args' => [%notify_opts]
    );

    if ( !Whostmgr::ACLS::hasroot() ) {
        Cpanel::Notify::Deferred::notify(
            'class'            => 'upacct::Notify',
            'application'      => 'upacct::Notify',
            'constructor_args' => [ %notify_opts, 'to' => $ENV{'REMOTE_USER'}, 'username' => $ENV{'REMOTE_USER'} ]
        );
    }

    #NOTE: This needs to happen after the cpuser file is saved because
    #Cpanel::ConfigFiles::Apache::Config uses cpuser to determine whether a user has
    #CGI pivileges or not.
    if ($changed_hascgi) {
        eval { require Cpanel::ConfigFiles::Apache::vhost; 1 } or die "Cannot load Cpanel::ConfigFiles::Apache::vhost: $!";
        Cpanel::ConfigFiles::Apache::vhost::update_domains_vhosts( @{ $cpuser_data->{'DOMAINS'} }, $cpuser_data->{'DOMAIN'} );
    }

    $output .= "<span class=\"b2\">Warning, this will not change shared IP accounts to dedicated IP accounts, or the reverse.</span>\n";

    $locale ||= Cpanel::Locale->get_handle();

    #
    # We only consider the enabledigest option when we setup the account.
    # Since we allow any user to enable it, we do not want to change it
    # when they change the package.   The package setting only defines
    # the inital state when the account is first setup.
    #
    $output .= "<span class=\"b2\">" . $locale->maketext("Warning: Changing a user’s package does not affect their Digest Authentication settings.") . "</span>\n";

    Cpanel::Services::Cpsrvd::signal_users_cpsrvd_to_reload($user);

    if ( !$OPTS{'skip_updateuserdomains'} ) {
        require Cpanel::Config::userdata::CacheQueue::Adder;
        require Cpanel::ServerTasks;
        Cpanel::Config::userdata::CacheQueue::Adder->add($user);
        Cpanel::ServerTasks::schedule_tasks( ['CpDBTasks'], [ [ 'update_userdomains', { 'delay_seconds' => 60 } ], [ 'update_userdata_cache', { 'delay_seconds' => 60 } ] ] );
    }

    Cpanel::Hooks::hook(
        {
            'category' => 'Whostmgr',
            'event'    => 'Accounts::change_package',
            'stage'    => 'post',
        },
        {
            'cur_pkg' => $cur_pkg,
            'new_pkg' => $pkg,
            'user'    => $user,
        },
    );

    $output .= "</pre>";

    return ( 1, "Account Upgrade/Downgrade Complete for $user", $output );
}

sub _set_modular_components ( $cpuser_data, $pkg_hr, $output_sr ) {    ## no critic qw(ManyArgs)
    for my $component ( Whostmgr::Packages::Info::Modular::get_enabled_components() ) {
        my $pkg_value    = $pkg_hr->{ $component->name_in_package() };
        my $cur_value_sr = \$cpuser_data->{ $component->name_in_cpuser() };

        my $mismatched = ( $component->type() eq 'numeric' ) ? ( $$cur_value_sr != $pkg_value ) : ( $$cur_value_sr ne $pkg_value );

        if ($mismatched) {
            $$output_sr .= $locale->maketext( "[_1]: Changing from “[_2]” to “[_3]”.", $component->label(), $$cur_value_sr, $pkg_value ) . "\n";

            try {
                $component->do_modifyacct( $cpuser_data->{'USER'}, $$cur_value_sr, $pkg_value );
            }
            catch {
                $$output_sr .= $_;
            };

            $$cur_value_sr = $pkg_value;
        }
    }

    return;
}

sub restart_services_after_account_upgrade {

    require Cpanel::Rlimit;
    Cpanel::Rlimit::set_rlimit_to_infinity();

    require Cpanel::HttpUtils::ApRestart::BgSafe;
    Cpanel::HttpUtils::ApRestart::BgSafe::restart();

    require Cpanel::FtpUtils::Server;
    if ( Cpanel::FtpUtils::Server::using_proftpd() ) {
        require Cpanel::Signal;
        Cpanel::Signal::send_hup_proftpd();
    }

    return;
}

1;
